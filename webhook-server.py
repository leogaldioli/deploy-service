#!/usr/bin/env python3
"""
deploy-service — Webhook server multi-projeto para deploy automatico via GitHub push events.
Substitui GitHub Actions para deploys em VPS propria.

Cada projeto e configurado em projects.json. Um unico server atende todos os repos.
"""

import hashlib
import hmac
import json
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime
from pathlib import Path

BASE_DIR = Path(__file__).parent.resolve()
CONFIG_FILE = BASE_DIR / "projects.json"
LOG_FILE = BASE_DIR / "webhook.log"


def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def load_projects():
    try:
        with open(CONFIG_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        log(f"ERROR loading config: {e}")
        return {}


def verify_signature(payload, signature, secret):
    if not signature or not secret:
        return False
    expected = "sha256=" + hmac.new(
        secret.encode(), payload, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/deploy":
            self.send_response(404)
            self.end_headers()
            return

        content_length = int(self.headers.get("Content-Length", 0))
        if content_length > 1_000_000:
            self.send_response(413)
            self.end_headers()
            return

        payload = self.rfile.read(content_length)

        try:
            data = json.loads(payload)
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            return

        repo_name = data.get("repository", {}).get("full_name", "")
        if not repo_name:
            log("ERROR: No repository in payload")
            self.send_response(400)
            self.end_headers()
            return

        projects = load_projects()
        project = projects.get(repo_name)
        if not project:
            log(f"ERROR: Unknown repo {repo_name}")
            self.send_response(404)
            self.end_headers()
            self.wfile.write(f"Unknown repo: {repo_name}".encode())
            return

        # Verify HMAC signature
        secret = project.get("secret", "")
        if secret:
            signature = self.headers.get("X-Hub-Signature-256", "")
            if not verify_signature(payload, signature, secret):
                log(f"ERROR: Invalid signature for {repo_name}")
                self.send_response(403)
                self.end_headers()
                self.wfile.write(b"Invalid signature")
                return
        else:
            log(f"WARN: No secret configured for {repo_name}")

        # Check branch
        ref = data.get("ref", "")
        target_branch = project.get("branch", "main")
        if ref != f"refs/heads/{target_branch}":
            log(f"[{repo_name}] Ignoring push to {ref}")
            self.send_response(200)
            self.end_headers()
            self.wfile.write(f"Ignored: not {target_branch}".encode())
            return

        pusher = data.get("pusher", {}).get("name", "unknown")
        commit = data.get("head_commit", {}).get("message", "")[:80]
        deploy_script = project.get("deploy_script", "")

        if not deploy_script:
            log(f"ERROR: No deploy_script for {repo_name}")
            self.send_response(500)
            self.end_headers()
            return

        log(f"[{repo_name}] Deploy triggered by {pusher}: {commit}")

        project_log = project.get("log_file", str(LOG_FILE))
        try:
            subprocess.Popen(
                ["/bin/bash", deploy_script],
                stdout=open(project_log, "a"),
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        except Exception as e:
            log(f"[{repo_name}] ERROR starting deploy: {e}")
            self.send_response(500)
            self.end_headers()
            return

        self.send_response(200)
        self.end_headers()
        self.wfile.write(f"Deploy started for {repo_name}".encode())

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            projects = load_projects()
            self.wfile.write(
                f"ok — {len(projects)} project(s) configured".encode()
            )
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        pass


def main():
    port = 9876
    projects = load_projects()
    log(f"deploy-service starting on port {port} — {len(projects)} project(s)")
    for name in projects:
        log(f"  - {name} → {projects[name].get('deploy_script', '?')}")
    server = HTTPServer(("0.0.0.0", port), WebhookHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("Shutting down")
        server.shutdown()


if __name__ == "__main__":
    main()
