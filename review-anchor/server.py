"""
Zero-dependency local HTTP server for Review Anchor Web GUI.
Serves static assets and provides REST API for plan data, git status,
pending-push tag management, and comment persistence.
"""

from http.server import HTTPServer, SimpleHTTPRequestHandler
import json
import os
import subprocess
import sys
import webbrowser
try:
    from .tui.git_anchoring import GitAnchoring
    from .tui.markdown_parser import MarkdownParser, MarkdownLine
    from .tui.clipboard import Clipboard
except (ImportError, ValueError):
    from tui.git_anchoring import GitAnchoring
    from tui.markdown_parser import MarkdownParser, MarkdownLine
    from tui.clipboard import Clipboard


class ReviewAnchorHandler(SimpleHTTPRequestHandler):
    plan_path = "implementation_plan.md"
    repo_root = os.getcwd()
    web_dir = os.path.join(os.path.dirname(__file__), "web")

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=self.web_dir, **kwargs)

    def do_GET(self):
        if self.path == "/api/plan":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()

            git_anchor = GitAnchoring(repo_root=self.repo_root, plan_path=self.plan_path)
            lines = []
            if os.path.exists(self.plan_path):
                parsed = MarkdownParser.parse_file(self.plan_path)
                lines = [
                    {
                        "line_number": l.line_number,
                        "raw_text": l.raw_text,
                        "line_type": l.line_type,
                        "heading_level": l.heading_level,
                        "heading_slug": l.heading_slug,
                        "alert_type": l.alert_type,
                        "alert_body": l.alert_body
                    }
                    for l in parsed
                ]

            tag_hash, is_at_tag = git_anchor.get_pending_push_info()

            data = {
                "filename": os.path.basename(self.plan_path),
                "model_header": git_anchor.model_header,
                "commit_mode": git_anchor.commit_mode,
                "author": git_anchor.author_name,
                "branch": git_anchor.get_current_branch(),
                "default_branch": git_anchor.get_default_branch(),
                "pending_push_hash": tag_hash,
                "is_at_pending_push": is_at_tag,
                "lines": lines
            }
            self.wfile.write(json.dumps(data).encode("utf-8"))
            return

        elif self.path == "/api/comments":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()

            git_anchor = GitAnchoring(repo_root=self.repo_root, plan_path=self.plan_path)
            comments = [
                {
                    "line_number": c.line_number,
                    "line_text": c.line_text,
                    "section_name": c.section_name,
                    "section_slug": c.section_slug,
                    "comment_text": c.comment_text,
                    "timestamp": c.timestamp,
                    "author": c.author
                }
                for c in git_anchor.get_comments()
            ]
            self.wfile.write(json.dumps(comments).encode("utf-8"))
            return

        return super().do_GET()

    def do_POST(self):
        content_len = int(self.headers.get("Content-Length", 0))
        post_data = self.rfile.read(content_len).decode("utf-8")

        if self.path == "/api/comments":
            try:
                comments_list = json.loads(post_data)
                git_anchor = GitAnchoring(repo_root=self.repo_root, plan_path=self.plan_path)
                git_anchor.comments.clear()
                
                for item in comments_list:
                    mline = MarkdownLine(
                        line_number=item["line_number"],
                        raw_text=item.get("line_text", ""),
                        line_type="text"
                    )
                    git_anchor.add_comment(
                        line=mline,
                        comment_text=item.get("comment_text", ""),
                        section_name=item.get("section_name", ""),
                        section_slug=item.get("section_slug", "")
                    )

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"status": "ok"}')
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode("utf-8"))
            return

        elif self.path == "/api/config":
            try:
                body = json.loads(post_data)
                git_anchor = GitAnchoring(repo_root=self.repo_root, plan_path=self.plan_path)
                if "model_name" in body:
                    git_anchor.model_header = body["model_name"]
                if "commit_mode" in body:
                    git_anchor.commit_mode = body["commit_mode"]
                git_anchor.save_config()

                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"status": "ok"}')
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode("utf-8"))
            return

        elif self.path == "/api/commit":
            try:
                body = json.loads(post_data) if post_data else {}
                git_anchor = GitAnchoring(repo_root=self.repo_root, plan_path=self.plan_path)
                mode = body.get("mode", git_anchor.commit_mode)
                prompt = body.get("prompt", None)

                ok, msg = git_anchor.execute_commit(general_prompt=prompt, mode=mode)
                self.send_response(200 if ok else 400)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"success": ok, "message": msg}).encode("utf-8"))
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode("utf-8"))
            return

        elif self.path == "/api/copy":
            try:
                body = json.loads(post_data)
                Clipboard.set_text(body.get("text", ""))
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b'{"status": "copied"}')
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode("utf-8"))
            return

        self.send_response(404)
        self.end_headers()


def start_gui_server(plan_path: str, repo_root: str, port: int = 8765, open_browser: bool = True):
    ReviewAnchorHandler.plan_path = plan_path
    ReviewAnchorHandler.repo_root = repo_root

    server_address = ("127.0.0.1", port)
    httpd = HTTPServer(server_address, ReviewAnchorHandler)
    url = f"http://127.0.0.1:{port}"
    print(f"⚓ Review Anchor GUI running at: {url}")
    print("Press Ctrl+C to stop the server.")

    if open_browser:
        webbrowser.open(url)

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping Review Anchor GUI server.")
        httpd.server_close()
