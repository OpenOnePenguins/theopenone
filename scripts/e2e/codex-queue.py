#!/usr/bin/env python3
"""Real Codex TUI + production AgentRunner, isolated home and local fake model.

Build driver with scripts/test-codex-queue.sh. Never uses host cursor, real
conversations, sign-in, or a paid model. Requires localhost socket permission.
"""
import fcntl
import http.server
import json
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import tempfile
import termios
import threading
import time


class Model(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        item = {"id": "msg_probe", "type": "message", "role": "assistant", "status": "completed",
                "content": [{"type": "output_text", "text": "Isolated response", "annotations": []}]}
        events = [
            ("response.created", {"response": {"id": "resp_probe", "status": "in_progress", "output": []}}),
            ("response.output_item.done", {"output_index": 0, "item": item}),
            ("response.completed", {"response": {"id": "resp_probe", "status": "completed", "output": [item],
                                                "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2}}}),
        ]
        body = "".join("event: " + name + "\ndata: " + json.dumps(dict(type=name, **value)) + "\n\n"
                       for name, value in events).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main(shared=False):
    driver = Path(__file__).resolve().parents[2] / ".build/native/codex-queue-driver"
    assert driver.is_file(), "Build with scripts/test-codex-queue.sh first"
    server = http.server.HTTPServer(("127.0.0.1", 0), Model)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    with tempfile.TemporaryDirectory(prefix="open-one-queue-e2e-") as temporary:
        home = Path(temporary)
        project = home / "project"
        project.mkdir()
        (home / "config.toml").write_text(
            'model_provider = "probe"\nmodel = "probe"\ncheck_for_update_on_startup = false\n'
            '[model_providers.probe]\nname = "Isolated model"\n'
            f'base_url = "http://127.0.0.1:{server.server_port}/v1"\n'
            'wire_api = "responses"\nrequires_openai_auth = false\n'
            'request_max_retries = 0\nstream_max_retries = 0\n'
            f'[projects.{json.dumps(str(project))}]\ntrust_level = "trusted"\n'
        )
        environment = dict(os.environ, CODEX_HOME=str(home), TERM="xterm-256color")
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        process = subprocess.Popen(
            ["codex"] + ([] if shared else ["--no-daemon"]) + ["--no-alt-screen", "-C", str(project), "Initial isolated probe"],
            stdin=slave, stdout=slave, stderr=slave, env=environment, start_new_session=True,
        )
        os.close(slave)

        def history():
            files = list(home.glob("sessions/**/*.jsonl"))
            if not files:
                return []
            result = []
            for line in files[0].read_text().splitlines():
                try:
                    result.append(json.loads(line))
                except json.JSONDecodeError:
                    pass  # Concurrent final line may still be in flight.
            return result

        def wait_until(predicate, timeout=40):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if predicate():
                    return
                assert process.poll() is None, "isolated terminal exited unexpectedly"
                if select.select([master], [], [], 0.1)[0]:
                    data = os.read(master, 65536)
                    if b"\x1b[6n" in data:
                        os.write(master, b"\x1b[1;1R")
                    if b"\x1b[c" in data:
                        os.write(master, b"\x1b[?1;2c")
            raise AssertionError("timed out waiting for isolated Codex turn")

        def completed():
            return sum(o.get("payload", {}).get("type") == "task_complete" for o in history())

        def locked(thread):
            with (home / "thread-writer-locks" / (thread + ".lock")).open("rb") as file:
                try:
                    fcntl.flock(file, fcntl.LOCK_SH | fcntl.LOCK_NB)
                    fcntl.flock(file, fcntl.LOCK_UN)
                    return False
                except BlockingIOError:
                    return True

        try:
            wait_until(lambda: completed() >= 1)
            thread = history()[0]["payload"]["id"]
            assert locked(thread), "original terminal must retain its writer lock between turns"
            message = "QUEUED_ISOLATED_PROBE"
            queued_at = time.monotonic()
            delivery = subprocess.run([str(driver), str(home), str(project), thread, message],
                                      env=environment, capture_output=True, text=True, timeout=45)
            assert delivery.returncode == 0, delivery.stdout + delivery.stderr
            assert f"for thread {thread}." in delivery.stdout
            accepted_at = time.monotonic()
            wait_until(lambda: completed() >= 2)
            print(f"TIMING ({'shared' if shared else 'embedded'}): queue receipt {accepted_at - queued_at:.3f}s; terminal response {time.monotonic() - queued_at:.3f}s", flush=True)
            users = [o["payload"] for o in history() if o["type"] == "response_item"
                     and o["payload"].get("role") == "user"]
            assert sum(any(c.get("text") == message for c in item.get("content", [])) for item in users) == 1
            assert process.poll() is None and locked(thread), "delivery must keep original terminal and writer alive"
            assert len(list(home.glob("sessions/**/*.jsonl"))) == 1, "must not fork or create a second conversation"
            print(f"PASS: production AgentRunner queued into a live {'shared' if shared else '--no-daemon'} terminal; original thread answered once, without releasing its writer lock")
        finally:
            process.terminate()
            try:
                process.wait(timeout=4)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            os.close(master)
            if shared:
                # CODEX_HOME points exclusively at this test's TemporaryDirectory.
                subprocess.run(["codex", "app-server", "daemon", "stop"], env=environment, capture_output=True, timeout=15, check=True)
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
    main(shared=True)
