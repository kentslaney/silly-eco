"""
Local web view -- the same exchange, in a browser window you can size and
re-font to line up with the Antigravity IDE review pane.

Standard library only, bound to loopback.  Like the TUI, it never contacts a
model API: it copies the composed prompt to the clipboard and takes the
response back by paste.
"""

from http.server import HTTPServer, SimpleHTTPRequestHandler
import json
import os
import sys
import webbrowser
from typing import Optional

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from tui.clipboard import Clipboard  # noqa: E402
from tui.exchange import Anchor, Exchange, blob_rev, now_stamp  # noqa: E402
from tui.git_anchoring import Config, Git  # noqa: E402
from tui.markdown_parser import MarkdownParser  # noqa: E402
from tui.store import ReviewStore  # noqa: E402


class State:
    """Everything the handler needs, resolved once at startup."""

    doc_path = "implementation_plan.md"
    repo_root = os.getcwd()

    @classmethod
    def git(cls) -> Git:
        return Git(cls.repo_root)

    @classmethod
    def store(cls) -> ReviewStore:
        return ReviewStore(cls.repo_root)

    @classmethod
    def config(cls) -> Config:
        return Config(cls.repo_root)

    @classmethod
    def doc_rel(cls) -> str:
        return os.path.relpath(cls.doc_path, cls.repo_root)

    @classmethod
    def exchange(cls, number: Optional[int] = None) -> Exchange:
        store = cls.store()
        ex = store.load(number) if number else (store.current() or store.latest())
        if ex is None:
            ex = store.create(model=str(cls.config()["model"]), doc=cls.doc_rel())
        return ex


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=os.path.join(HERE, "web"), **kwargs)

    def log_message(self, fmt, *args):  # quiet
        pass

    # -- helpers ---------------------------------------------------------
    def _send(self, payload, code: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except ValueError:
            return {}

    def _state(self, number: Optional[int] = None) -> dict:
        git, store, config = State.git(), State.store(), State.config()
        ex = State.exchange(number)
        parsed = (
            MarkdownParser.parse_file(State.doc_path)
            if os.path.exists(State.doc_path)
            else []
        )
        tag, at_tag = git.tag_info()
        return {
            "doc": {
                "name": os.path.basename(State.doc_path),
                "rel": State.doc_rel(),
                "rev": blob_rev(State.doc_path),
                "lines": [
                    {
                        "n": l.line_number,
                        "text": l.raw_text,
                        "type": l.line_type,
                        "level": l.heading_level,
                        "slug": l.heading_slug,
                        "alert": l.alert_type,
                    }
                    for l in parsed
                ],
            },
            "git": {
                "branch": git.current_branch(),
                "default": git.default_branch(),
                "pending_push": tag,
                "at_pending_push": at_tag,
                "dirty": git.is_dirty(),
                "author": git.author(),
            },
            "exchange": {
                "number": store.number_of(ex),
                "path": store.rel(ex.path) if ex.path else "",
                "meta": ex.meta,
                "prompt": ex.prompt,
                "response": ex.response,
                "notes": ex.notes,
                "stale": bool(ex.meta.get("doc-rev")) and ex.meta.get("doc-rev") != blob_rev(State.doc_path),
                "anchors": [
                    {
                        "path": a.path,
                        "line": a.line,
                        "count": a.count,
                        "slug": a.slug,
                        "quote": a.quote,
                        "comment": a.comment,
                        "header": a.header(),
                    }
                    for a in ex.anchors
                ],
            },
            "commit_message": ex.commit_message(
                log_path=store.rel(ex.path) if ex.path else "",
                extra_trailers=config.extra_trailers,
                bare=bool(config["bare_commit"]),
            ),
            "composed_prompt": ex.compose_prompt(),
            "bare": bool(config["bare_commit"]),
            "log": [
                {"number": n, "name": os.path.basename(p), "state": Exchange.load(p).state}
                for n, p in store.entries()
            ],
        }

    # -- routes ----------------------------------------------------------
    def do_GET(self):
        if self.path.startswith("/api/state"):
            number = None
            if "?" in self.path:
                query = self.path.split("?", 1)[1]
                for pair in query.split("&"):
                    key, _, value = pair.partition("=")
                    if key == "n" and value.isdigit():
                        number = int(value)
            return self._send(self._state(number))
        return super().do_GET()

    def do_POST(self):
        body = self._read()
        number = body.get("number")
        ex = State.exchange(int(number) if number else None)
        store, config = State.store(), State.config()

        if self.path == "/api/exchange":
            for key in ("prompt", "response", "notes"):
                if key in body:
                    setattr(ex, key, body[key])
            for key in ("model", "subject"):
                if key in body and body[key]:
                    ex.meta[key] = body[key]
                    if key == "model":
                        config["model"] = body[key]
            ex.save()
            return self._send(self._state(store.number_of(ex)))

        if self.path == "/api/anchor":
            lines = MarkdownParser.parse_file(State.doc_path)
            start = int(body.get("line", 1))
            count = max(1, int(body.get("count", 1)))
            quote = [l.raw_text for l in lines if start <= l.line_number < start + count]
            slug = ""
            for l in lines:
                if l.line_number > start:
                    break
                if l.line_type == "heading":
                    slug = l.heading_slug
            ex.anchors.append(
                Anchor(
                    path=State.doc_rel(),
                    line=start,
                    count=count,
                    slug=slug,
                    quote=quote,
                    comment=str(body.get("comment", "")).strip(),
                )
            )
            ex.meta.setdefault("doc", State.doc_rel())
            ex.meta["doc-rev"] = blob_rev(State.doc_path)
            ex.sort_anchors()
            ex.save()
            return self._send(self._state(store.number_of(ex)))

        if self.path == "/api/anchor/delete":
            line = int(body.get("line", 0))
            ex.anchors = [a for a in ex.anchors if a.line != line]
            ex.save()
            return self._send(self._state(store.number_of(ex)))

        if self.path == "/api/verify":
            lines = [l.raw_text for l in MarkdownParser.parse_file(State.doc_path)]
            moved = lost = 0
            for a in ex.anchors:
                if a.matches(lines):
                    continue
                found = a.relocate(lines)
                if found:
                    a.line, moved = found, moved + 1
                else:
                    lost += 1
            ex.meta["doc-rev"] = blob_rev(State.doc_path)
            ex.save()
            state = self._state(store.number_of(ex))
            state["message"] = f"{moved} relocated, {lost} lost"
            return self._send(state)

        if self.path == "/api/bare":
            config["bare_commit"] = bool(body.get("bare"))
            return self._send(self._state(store.number_of(ex)))

        if self.path == "/api/new":
            ex = store.create(
                model=str(config["model"]), doc=State.doc_rel(), title=str(body.get("title", ""))
            )
            return self._send(self._state(store.number_of(ex)))

        if self.path == "/api/clip":
            where = Clipboard.set_text(str(body.get("text", "")))
            return self._send({"ok": bool(where), "where": where})

        if self.path == "/api/paste":
            return self._send({"text": Clipboard.get_text()})

        if self.path == "/api/commit":
            ex.meta["state"] = "closed"
            ex.meta.setdefault("date", now_stamp())
            ex.save()
            message = ex.commit_message(
                log_path=store.rel(ex.path) if ex.path else "",
                extra_trailers=config.extra_trailers,
                bare=bool(config["bare_commit"]),
            )
            ok, out = State.git().commit(message)
            if not ok:
                ex.meta["state"] = "open"
                ex.save()
                return self._send({"ok": False, "message": out}, 400)
            store.create(model=ex.model, doc=State.doc_rel())
            state = self._state()
            state["message"] = out
            return self._send(state)

        return self._send({"error": "not found"}, 404)


def start_gui_server(doc_path: str, repo_root: str, port: int = 8765, open_browser: bool = True):
    State.doc_path = doc_path
    State.repo_root = repo_root
    Clipboard.fallback_dir = repo_root
    httpd = HTTPServer(("127.0.0.1", port), Handler)
    url = f"http://127.0.0.1:{port}"
    print(f"review anchor · {url}   (ctrl-c to stop)")
    if open_browser:
        webbrowser.open(url)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print()
    finally:
        httpd.server_close()
