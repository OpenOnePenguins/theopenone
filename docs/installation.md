# Install The Open One from source

The Open One is a native macOS app. This repository includes the desktop app, optional phone web app, landing page, and launch-video source. A notarized installer is not included.

## Requirements

- macOS 13 or newer.
- Apple's Command Line Tools, installed with `xcode-select --install`.
- Python 3 available as `python3`, used by build/signing tools and the agent bridge.
- An installed, signed-in Claude Code or Codex CLI for live agents. Guided setup helps check these after launch.
- Node.js and npm only if building the optional phone interface or launch video. Use a Node version supported by Expo SDK 57 for the phone build.

Download [the repository](https://github.com/OpenOnePenguins/theopenone) with GitHub's **Code → Download ZIP**, or clone it:

```sh
git clone https://github.com/OpenOnePenguins/theopenone.git
cd theopenone
```

Run the following commands from that folder.

## Desktop build

```sh
bash scripts/build.sh
open "dist/Open One.app"
```

The standalone builder compiles SwiftUI/AppKit sources, bundles the Python helpers and brand assets, and signs the app. It builds for the Mac's current architecture. You can keep the app in `dist`, or quit it and copy **Open One.app** into Applications before reopening it.

First launch opens **Set up Open One**. Select Claude Code, Codex, or both; check installation and sign-in; choose a project; then click **Verify connections**. This explicitly sends a short hello through each selected agent using your own account. Setup completes after receiving an actual reply. **Set up later** defers it; reopen it from **Settings → Connect agents — guided setup**. See [onboarding](onboarding.md) for the complete flow and troubleshooting.

To inspect the UI without provider accounts, quit the running instance and launch demo mode:

```sh
open "dist/Open One.app" --args --demo
```

Demo conversations are samples and do not send agent requests.

## Include the phone interface

Export the web app **before** building the Mac app. From the repository root:

```sh
cd mobile
npm ci
npx expo export --platform web
cd ..
bash scripts/build.sh
open "dist/Open One.app"
```

The desktop builder copies `mobile/dist` into the app when it exists. On the Mac, choose **Remote access → Local Wi-Fi only → Connect phone**. Scan its QR in Safari on a phone on the same network. Keep the Mac awake and The Open One running. See [phone setup](phone-setup.md) and the [mobile developer guide](../mobile/README.md).

## Local signing and macOS permissions

The default build creates or reuses a per-user development certificate in a dedicated Keychain. After the first build, complete its one-time trust setup:

```sh
python3 scripts/sign-app.py --trust-local-certificate 'dist/Open One.app'
```

This trusts that certificate for code signing in your user domain. Preserve `~/Library/Application Support/Open One/signing` across rebuilds: it contains private signing material and must never be committed or shared. Reusing the identity avoids changing the app's identity on every rebuild.

Microphone/Speech and Screen Recording access are requested when you use those features. After granting Screen Recording, quit and reopen The Open One. If migrating from an older ad hoc build, remove its obsolete Screen Recording entry and grant access to the current app.

Distribution builders can set `OPEN_ONE_SIGNING_IDENTITY` to an Apple-issued signing identity. `OPEN_ONE_SIGNING_IDENTITY=-` explicitly selects ad hoc signing; permission continuity across rebuilds is then lost. Neither option notarizes the app automatically.

## Existing conversations and command approvals

Enable transcript discovery and add the desired projects under **Tracked worktrees**. A new terminal appears after its provider saves a conversation, normally following its first message. Hover the activity dots to open **Your agents**; use Refresh if needed. Double-tap **Control** to open Talk.

The Open One can queue follow-ups into an active Codex conversation and resume eligible idle sessions. An active Claude session must be closed in its original terminal before continuation. The app never removes writer locks or bypasses provider permissions.

Command requests for sessions run by The Open One appear with **Approve once** and **Deny**, including a two-second Undo interval. Ordinary observed Codex/Claude terminals still require confirmation in their owning terminal; connected Herdr terminals expose explicit approval keys on the Mac. Phone chat does not forward approval controls. See [command approvals](approvals.md).

## Update and verify

Update your checkout, repeat the optional web export if used, then rebuild. Quit the old app before opening the new bundle. Conversation data lives separately in `~/Library/Application Support/Open One`; set `OPEN_ONE_HOME` to use an isolated data directory.

```sh
bash scripts/test.sh
bash scripts/test-onboarding.sh
```

See the [release checklist](feature-parity.md) for additional integration and device checks. Never point fixture tests at your normal application data directory.
