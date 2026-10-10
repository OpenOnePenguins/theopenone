#!/usr/bin/env python3
"""Keep local development builds on one certificate without changing root trust."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys
import tempfile

SIGNING = Path.home() / "Library/Application Support/Open One/signing"
CONFIG = SIGNING / "identity.json"
KEYCHAIN = SIGNING / "development.keychain-db"


def run(*args, **kwargs):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True, **kwargs)
    if result.returncode:
        # Never include argv: Keychain commands contain generated passwords.
        raise RuntimeError(f"{Path(args[0]).name} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def local_identity():
    if CONFIG.exists():
        config = json.loads(CONFIG.read_text())
        if not KEYCHAIN.exists():
            raise RuntimeError("The saved signing Keychain is missing. Restore it; do not rotate the identity silently.")
        return config
    if KEYCHAIN.exists():
        raise RuntimeError("Incomplete signing setup: Keychain exists without identity.json. Recover it before rebuilding.")
    password = secrets.token_urlsafe(48)
    # Persist recovery material before creating the Keychain. It is never logged.
    recovery = SIGNING / "setup-password"
    recovery.write_text(password)
    recovery.chmod(0o600)
    with tempfile.TemporaryDirectory(prefix="setup-", dir=SIGNING) as directory:
        temporary = Path(directory)
        config_path = temporary / "certificate.cnf"
        config_path.write_text("""[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = Open One Local Development
[extensions]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
""")
        key, cert, archive = (temporary / name for name in ("key.pem", "cert.pem", "identity.p12"))
        run("/usr/bin/openssl", "req", "-new", "-newkey", "rsa:3072", "-nodes", "-x509", "-sha256",
            "-days", "3650", "-config", config_path, "-keyout", key, "-out", cert)
        environment = dict(os.environ, OPEN_ONE_P12_PASSWORD=password)
        run("/usr/bin/openssl", "pkcs12", "-export", "-inkey", key, "-in", cert, "-out", archive,
            "-passout", "env:OPEN_ONE_P12_PASSWORD", env=environment)
        run("/usr/bin/security", "create-keychain", "-p", password, KEYCHAIN)
        run("/usr/bin/security", "unlock-keychain", "-p", password, KEYCHAIN)
        run("/usr/bin/security", "import", archive, "-k", KEYCHAIN, "-f", "pkcs12", "-P", password,
            "-x", "-T", "/usr/bin/codesign")
        run("/usr/bin/security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", password, KEYCHAIN)
        der = subprocess.run(["/usr/bin/openssl", "x509", "-in", str(cert), "-outform", "DER"],
                             check=True, capture_output=True).stdout
        config = {"identity": hashlib.sha1(der).hexdigest().upper(), "password": password}
        CONFIG.write_text(json.dumps(config))
        CONFIG.chmod(0o600)
        recovery.unlink()
        return config


def sign(app, trust_local=False):
    explicit = os.environ.get("OPEN_ONE_SIGNING_IDENTITY")
    if explicit:
        if explicit == "-":
            print("Warning: explicit ad hoc signing; privacy grants may break after rebuilds.", file=sys.stderr)
        for target in (app / "Contents/Frameworks/libOneCore.dylib", app):
            run("/usr/bin/codesign", "--force", "--sign", explicit, target)
    else:
        SIGNING.mkdir(parents=True, exist_ok=True, mode=0o700)
        SIGNING.chmod(0o700)
        with (SIGNING / "signing.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            config = local_identity()
            try:
                search_list = shlex.split(run("/usr/bin/security", "list-keychains", "-d", "user"))
                if str(KEYCHAIN) not in search_list:
                    run("/usr/bin/security", "list-keychains", "-d", "user", "-s", *search_list, KEYCHAIN)
                run("/usr/bin/security", "unlock-keychain", "-p", config["password"], KEYCHAIN)
                if trust_local:
                    certificate = SIGNING / "certificate.pem"
                    certificate.write_text(run("/usr/bin/security", "find-certificate", "-c",
                                               "Open One Local Development", "-p", KEYCHAIN) + "\n")
                    # User-domain trust restricted to the code-signing policy.
                    # No TLS or system root-store trust.
                    run("/usr/bin/security", "add-trusted-cert", "-r", "trustRoot", "-p", "codeSign",
                        "-k", KEYCHAIN, certificate)
                valid = run("/usr/bin/security", "find-identity", "-v", "-p", "codesigning", KEYCHAIN)
                if config["identity"] not in valid:
                    raise RuntimeError("Local signing certificate needs its one-time code-signing trust setup. "
                                       "Run: python3 scripts/sign-app.py --trust-local-certificate 'dist/Open One.app'")
                for target in (app / "Contents/Frameworks/libOneCore.dylib", app):
                    run("/usr/bin/codesign", "--force", "--timestamp=none", "--keychain", KEYCHAIN,
                        "--sign", config["identity"], target)
            finally:
                run("/usr/bin/security", "lock-keychain", KEYCHAIN)
        print("Signed with persistent Open One local development identity.")
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)


if __name__ == "__main__":
    os.umask(0o077)
    try:
        arguments = sys.argv[1:]
        trust_local = "--trust-local-certificate" in arguments
        if trust_local:
            arguments.remove("--trust-local-certificate")
        if len(arguments) != 1:
            raise RuntimeError("Usage: python3 scripts/sign-app.py [--trust-local-certificate] path/to/app")
        sign(Path(arguments[0]).resolve(), trust_local)
    except (RuntimeError, OSError, ValueError) as error:
        sys.exit(str(error))
