import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

CLI = str(Path(__file__).with_name("one"))


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.env = {**os.environ, "OPEN_ONE_HOME": str(self.root)}

    def tearDown(self):
        self.temp.cleanup()

    def run_cli(self, *args):
        return subprocess.run([sys.executable, CLI, *args], env=self.env, text=True, capture_output=True)

    def test_event_is_atomic_and_private(self):
        result = self.run_cli("done", "--agent", "test", "--text", "Finished")
        self.assertEqual(result.returncode, 0, result.stderr)
        files = list((self.root / "events").iterdir())
        self.assertEqual(len(files), 1)
        self.assertEqual(files[0].suffix, ".json")
        self.assertEqual(files[0].stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(files[0].read_text())["text"], "Finished")

    def test_question_waits_for_matching_reply(self):
        process = subprocess.Popen([sys.executable, CLI, "ask", "--agent", "test", "--question", "Which?", "--option", "First", "--option", "Second", "--json", "--timeout", "5"], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 3
            files = []
            while not files and time.monotonic() < deadline:
                files = list((self.root / "events").glob("*.json"))
                time.sleep(0.02)
            self.assertTrue(files)
            event = json.loads(files[0].read_text())
            self.assertEqual(event["choices"], ["First", "Second"])
            self.assertIsNone(process.poll())
            request = event["requestID"]
            filename = base64.urlsafe_b64encode(request.encode()).decode().rstrip("=")
            reply = {"agentID": "test", "requestID": request, "text": "Second", "choiceIndex": 1}
            temp = self.root / "replies" / "pending.tmp"
            temp.write_text(json.dumps(reply))
            temp.replace(self.root / "replies" / f"{filename}.json")
            output, errors = process.communicate(timeout=3)
            self.assertEqual(process.returncode, 0, errors)
            self.assertEqual(json.loads(output), reply)
            self.assertFalse(list((self.root / "replies").glob("*.json")))
        finally:
            if process.poll() is None:
                process.kill(); process.communicate()

    def test_timeout_does_not_supply_default_answer(self):
        result = self.run_cli("ask", "--agent", "test", "--question", "Continue?", "--option", "Yes", "--timeout", "0.1")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, "")
        self.assertIn("No answer was assumed", result.stderr)


if __name__ == "__main__":
    unittest.main()
