"""Integration tests for the MCP command-line helper using a local fake server."""

import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest


SECRET = "0123456789abcdef0123456789abcdef"
SCRIPT = Path(__file__).with_name("mcp_aufruf.sh")


class FakeMcp(http.server.BaseHTTPRequestHandler):
    authorizations = {}

    def do_POST(self):
        self.authorizations[self.server.server_port].append(
            self.headers.get("Authorization", "")
        )
        length = int(self.headers.get("Content-Length", "0"))
        request = json.loads(self.rfile.read(length))
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Mcp-Session-Id", "test-session")
        self.end_headers()
        if request.get("method") == "tools/call":
            response = {
                "jsonrpc": "2.0",
                "id": 2,
                "error": {"code": -32000, "message": f"Fehler {SECRET}"},
            }
        else:
            response = {"jsonrpc": "2.0", "result": {}}
        self.wfile.write(json.dumps(response).encode())

    def log_message(self, _format, *_args):
        pass


class McpAufrufTest(unittest.TestCase):
    def setUp(self):
        FakeMcp.authorizations = {}
        self.servers = []
        self.threads = []
        for _ in range(2):
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeMcp)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self.servers.append(server)
            self.threads.append(thread)
            FakeMcp.authorizations[server.server_port] = []

        self.temp = tempfile.TemporaryDirectory(prefix="mcp-aufruf-")
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        settings_dir = self.home / "Library" / "Application Support" / "moocp"
        settings_dir.mkdir(parents=True)
        self.args_file = self.root / "curl-args.txt"
        self.settings = settings_dir / "einstellungen.json"
        self.settings.write_text(
            json.dumps(
                {
                    "schluessel": SECRET,
                    "profile": [
                        {"name": "Moodle", "mcpName": "moodle", "port": self.servers[0].server_port},
                        {"name": "Moodle Test", "mcpName": "moodle-test", "port": self.servers[1].server_port},
                    ],
                }
            ),
            encoding="utf-8",
        )

        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        curl = shutil.which("curl")
        (fake_bin / "curl").write_text(
            "#!/bin/bash\n"
            'printf \'%s\\n\' "$@" >> "$MOOCP_TEST_CURL_ARGS_FILE"\n'
            f'exec "{curl}" "$@"\n',
            encoding="utf-8",
        )
        (fake_bin / "curl").chmod(0o755)
        self.environment = {
            **os.environ,
            "HOME": str(self.home),
            "APPDATA": "",
            "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
            "MOOCP_TEST_CURL_ARGS_FILE": str(self.args_file),
        }

    def tearDown(self):
        for server in self.servers:
            server.shutdown()
            server.server_close()
        self.temp.cleanup()

    def call(self, *extra_args):
        return subprocess.run(
            ["bash", str(SCRIPT), "testwerkzeug", "{}", *extra_args],
            capture_output=True,
            text=True,
            env=self.environment,
            check=False,
        )

    def assert_no_secret_leak(self, result):
        self.assertNotIn(SECRET, result.stdout)
        self.assertNotIn(SECRET, result.stderr)
        if self.args_file.exists():
            self.assertNotIn(SECRET, self.args_file.read_text(encoding="utf-8"))

    def test_macos_uses_selected_profile_and_redacts_error_response(self):
        result = self.call("moodle-test")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            FakeMcp.authorizations[self.servers[1].server_port],
            [f"Bearer {SECRET}"] * 3,
        )
        self.assertEqual(FakeMcp.authorizations[self.servers[0].server_port], [])
        self.assertIn("[geschwärzt]", result.stdout)
        self.assert_no_secret_leak(result)

    def test_without_selector_uses_first_profile(self):
        result = self.call()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            FakeMcp.authorizations[self.servers[0].server_port],
            [f"Bearer {SECRET}"] * 3,
        )
        self.assertEqual(FakeMcp.authorizations[self.servers[1].server_port], [])
        self.assertIn("[geschwärzt]", result.stdout)
        self.assert_no_secret_leak(result)

    def test_unknown_profile_fails_without_exposing_secret(self):
        result = self.call("unknown")

        self.assertEqual(result.returncode, 2)
        self.assertIn("Profil", result.stderr)
        self.assert_no_secret_leak(result)


if __name__ == "__main__":
    unittest.main()
