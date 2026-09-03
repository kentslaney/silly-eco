"""
Curses front end.

Left pane renders the design doc WYSIWYG, at an adjustable wrap width so the
line breaks can be matched side by side against the Antigravity IDE review
pane.  Right pane is the exchange: the prompt being drafted, the anchored
comments, the response pasted back, and the commit message they render to.

The tool never calls a model API.  ``y`` copies the composed prompt out, ``R``
pastes the response back in; in between you are in whatever chat window you
like.
"""

import curses
import os
import subprocess
import tempfile
from typing import List, Optional, Tuple

from .clipboard import Clipboard
from .exchange import Anchor, Exchange, blob_rev, now_stamp
from .git_anchoring import Config, Git
from .markdown_parser import MarkdownLine, MarkdownParser
from .store import ReviewStore
from .wysiwyg_renderer import WysiwygRenderer

TABS = ("commit", "prompt", "response", "anchors")


class ReviewAnchorTUI:
    def __init__(self, plan_path: str, repo_root: Optional[str] = None):
        self.git = Git(repo_root)
        self.repo_root = self.git.repo_root
        self.plan_path = plan_path
        self.doc_rel = os.path.relpath(plan_path, self.repo_root)
        self.config = Config(self.repo_root)
        self.store = ReviewStore(self.repo_root)
        Clipboard.fallback_dir = self.repo_root

        self.exchange = self.store.current() or self.store.create(
            model=str(self.config["model"]), doc=self.doc_rel
        )

        self.lines: List[MarkdownLine] = []
        self.cursor = 0
        self.scroll = 0
        self.mark: Optional[int] = None
        self.tab = 0
        self.pane_scroll = 0
        self.wrap_width = int(self.config["wrap_width"] or 80)
        self.split = True
        self.status = "? for help  ·  c comment  ·  y copy prompt  ·  R paste response  ·  C commit"
        self.load_doc()

    # -- document ---------------------------------------------------------
    def load_doc(self) -> None:
        if os.path.exists(self.plan_path):
            self.lines = MarkdownParser.parse_file(self.plan_path)
        else:
            self.lines = [MarkdownLine(1, f"# not found: {self.plan_path}", "heading", heading_level=1)]
        self.cursor = min(self.cursor, max(0, len(self.lines) - 1))

    def raw_lines(self) -> List[str]:
        return [l.raw_text for l in self.lines]

    def section_at(self, idx: int) -> Tuple[str, str]:
        for i in range(min(idx, len(self.lines) - 1), -1, -1):
            if self.lines[i].line_type == "heading":
                return self.lines[i].raw_text.lstrip("#").strip(), self.lines[i].heading_slug
        return "", ""

    def selection(self) -> Tuple[int, int]:
        if self.mark is None:
            return self.cursor, self.cursor
        return min(self.mark, self.cursor), max(self.mark, self.cursor)

    def anchored_lines(self) -> set:
        out = set()
        for a in self.exchange.anchors_for(self.doc_rel):
            lo, hi = a.span
            out.update(range(lo, hi + 1))
        return out

    def doc_is_stale(self) -> bool:
        rev = self.exchange.meta.get("doc-rev")
        return bool(rev) and rev != blob_rev(self.plan_path)

    # -- exchange ---------------------------------------------------------
    def save_exchange(self) -> None:
        self.exchange.sort_anchors()
        self.exchange.save()

    def log_rel(self) -> str:
        return self.store.rel(self.exchange.path) if self.exchange.path else ""

    def commit_message(self) -> str:
        return self.exchange.commit_message(
            log_path=self.log_rel(),
            extra_trailers=self.config.extra_trailers,
            bare=bool(self.config["bare_commit"]),
        )

    def switch(self, delta: int) -> None:
        entries = self.store.entries()
        if not entries:
            return
        cur = self.store.number_of(self.exchange)
        nums = [n for n, _ in entries]
        idx = nums.index(cur) if cur in nums else len(nums) - 1
        idx = max(0, min(len(nums) - 1, idx + delta))
        self.exchange = self.store.load(nums[idx]) or self.exchange
        doc = self.exchange.doc
        if doc:
            candidate = os.path.join(self.repo_root, doc)
            if os.path.exists(candidate):
                self.plan_path, self.doc_rel = candidate, doc
                self.load_doc()
        self.status = f"exchange {nums[idx]:04d} [{self.exchange.state}]"

    # -- main loop --------------------------------------------------------
    def run(self) -> None:
        curses.wrapper(self._loop)

    def _loop(self, stdscr) -> None:
        curses.curs_set(0)
        stdscr.keypad(True)
        WysiwygRenderer.init_colors()

        while True:
            max_y, max_x = stdscr.getmaxyx()
            stdscr.erase()
            if max_y < 8 or max_x < 40:
                stdscr.addstr(0, 0, "terminal too small")
                stdscr.refresh()
                if stdscr.getch() in (ord("q"), 27):
                    return
                continue

            if self.split and max_x >= 92:
                doc_w = max(46, int(max_x * 0.55))
                right_w = max_x - doc_w - 1
            else:
                doc_w, right_w = max_x, 0

            self._draw_doc(stdscr, max_y - 1, doc_w)
            if right_w:
                self._draw_pane(stdscr, max_y - 1, doc_w + 1, right_w)
            self._draw_status(stdscr, max_y - 1, max_x)
            stdscr.refresh()

            try:
                key = stdscr.getch()
            except KeyboardInterrupt:
                return
            if self._handle(stdscr, key, max_y) is False:
                return

    def _handle(self, stdscr, key: int, max_y: int):
        page = max(1, max_y - 4)
        if key in (ord("q"), 27):
            return False
        elif key in (curses.KEY_DOWN, ord("j")):
            self._move(1, max_y)
        elif key in (curses.KEY_UP, ord("k")):
            self._move(-1, max_y)
        elif key == curses.KEY_NPAGE:
            self._move(page, max_y)
        elif key == curses.KEY_PPAGE:
            self._move(-page, max_y)
        elif key == ord("g"):
            self.cursor = self.scroll = 0
        elif key == ord("G"):
            self.cursor = len(self.lines) - 1
            self.scroll = max(0, self.cursor - max_y + 4)
        elif key in (ord("+"), ord("=")):
            self.wrap_width = min(160, self.wrap_width + 2)
            self.config["wrap_width"] = self.wrap_width
            self.status = f"wrap {self.wrap_width}"
        elif key in (ord("-"), ord("_")):
            self.wrap_width = max(40, self.wrap_width - 2)
            self.config["wrap_width"] = self.wrap_width
            self.status = f"wrap {self.wrap_width}"
        elif key == ord("\t"):
            self.split = not self.split
        elif key in (ord("1"), ord("2"), ord("3"), ord("4")):
            self.tab = key - ord("1")
            self.pane_scroll = 0
        elif key == ord("J"):
            self.pane_scroll += 1
        elif key == ord("K"):
            self.pane_scroll = max(0, self.pane_scroll - 1)
        elif key == ord("v"):
            self.mark = None if self.mark is not None else self.cursor
            self.status = "range mark cleared" if self.mark is None else "range mark set"
        elif key in (ord("c"), ord("\n"), 10, 13):
            self._add_anchor(stdscr)
        elif key in (ord("d"), ord("x")):
            self._delete_anchor()
        elif key == ord("p"):
            self._paste_jump()
        elif key == ord("#"):
            self._goto_line(stdscr)
        elif key == ord("e"):
            self._edit_file(stdscr, self.exchange.path)
            self.exchange = Exchange.load(self.exchange.path)
            self.status = "reloaded exchange"
        elif key == ord("P"):
            self.exchange.prompt = self._edit_text(stdscr, self.exchange.prompt, "prompt.md")
            self.save_exchange()
            self.status = "prompt updated"
        elif key == ord("r"):
            self.exchange.response = self._edit_text(stdscr, self.exchange.response, "response.md")
            self.save_exchange()
            self.status = "response updated"
        elif key == ord("R"):
            text = Clipboard.get_text().strip()
            if text:
                self.exchange.response = text
                self.save_exchange()
                self.tab = 2
                self.status = f"pasted response ({len(text.splitlines())} lines)"
            else:
                self.status = "clipboard empty"
        elif key == ord("y"):
            where = Clipboard.set_text(self.exchange.compose_prompt())
            self.status = f"prompt + {len(self.exchange.anchors)} anchors → {where}"
        elif key == ord("Y"):
            where = Clipboard.set_text(self.commit_message())
            self.status = f"commit message → {where}"
        elif key == ord("m"):
            val = self._ask(stdscr, f"model [{self.exchange.model}]: ")
            if val:
                self.exchange.set("model", val)
                self.config["model"] = val
                self.save_exchange()
                self.status = f"model = {val}"
        elif key == ord("s"):
            val = self._ask(stdscr, f"subject [{self.exchange.subject}]: ")
            if val:
                self.exchange.set("subject", val)
                self.save_exchange()
                self.status = f"subject = {val}"
        elif key == ord("b"):
            self.config["bare_commit"] = not bool(self.config["bare_commit"])
            self.status = (
                "bare commit: subject only (pending-push style)"
                if self.config["bare_commit"]
                else "full commit: subject + prompt + anchors + trailers"
            )
        elif key == ord("V"):
            self._verify()
        elif key == ord("n"):
            title = self._ask(stdscr, "title for new exchange: ")
            self.exchange = self.store.create(
                model=str(self.config["model"]), doc=self.doc_rel, title=title
            )
            self.status = f"created {os.path.basename(self.exchange.path)}"
        elif key == ord("["):
            self.switch(-1)
        elif key == ord("]"):
            self.switch(1)
        elif key == ord("C"):
            self._commit(stdscr)
        elif key == ord("?"):
            self._help(stdscr)
        return True

    def _move(self, delta: int, max_y: int) -> None:
        self.cursor = max(0, min(len(self.lines) - 1, self.cursor + delta))
        height = max_y - 3
        if self.cursor < self.scroll:
            self.scroll = self.cursor
        elif self.cursor >= self.scroll + height:
            self.scroll = self.cursor - height + 1

    # -- anchors ----------------------------------------------------------
    def _add_anchor(self, stdscr) -> None:
        lo, hi = self.selection()
        first = self.lines[lo]
        quote = [self.lines[i].raw_text for i in range(lo, hi + 1)]
        name, slug = self.section_at(lo)
        text = self._ask(stdscr, f"comment L{first.line_number} (empty → $EDITOR): ")
        if not text:
            text = self._edit_text(stdscr, "", "comment.md")
        if not text.strip():
            self.status = "cancelled"
            return
        self.exchange.anchors.append(
            Anchor(
                path=self.doc_rel,
                line=first.line_number,
                count=hi - lo + 1,
                slug=slug,
                quote=quote,
                comment=text.strip(),
            )
        )
        self.exchange.meta.setdefault("doc", self.doc_rel)
        self.exchange.meta["doc-rev"] = blob_rev(self.plan_path)
        self.mark = None
        self.save_exchange()
        self.tab = 3
        self.status = f"anchored L{first.line_number}" + (f"-{self.lines[hi].line_number}" if hi > lo else "")

    def _delete_anchor(self) -> None:
        lo, hi = self.selection()
        nums = {self.lines[i].line_number for i in range(lo, hi + 1)}
        mine = (self.doc_rel, os.path.basename(self.doc_rel))

        def hits(anchor) -> bool:
            lo_a, hi_a = anchor.span
            return anchor.path in mine and bool(nums & set(range(lo_a, hi_a + 1)))

        before = len(self.exchange.anchors)
        self.exchange.anchors = [a for a in self.exchange.anchors if not hits(a)]
        self.save_exchange()
        self.status = f"removed {before - len(self.exchange.anchors)} anchor(s)"

    def _verify(self) -> None:
        raw = self.raw_lines()
        moved = stale = 0
        for a in self.exchange.anchors_for(self.doc_rel):
            if a.matches(raw):
                continue
            found = a.relocate(raw)
            if found:
                a.line = found
                _, a.slug = self.section_at(found - 1)
                moved += 1
            else:
                stale += 1
        self.exchange.meta["doc-rev"] = blob_rev(self.plan_path)
        self.save_exchange()
        self.status = f"verified: {moved} relocated, {stale} lost, {len(self.exchange.anchors)} total"

    # -- navigation helpers ----------------------------------------------
    def _paste_jump(self) -> None:
        clip = Clipboard.get_text().strip()
        if not clip:
            self.status = "clipboard empty"
            return
        needle = clip.splitlines()[0].strip().lower()
        for idx, line in enumerate(self.lines):
            if needle and needle in line.raw_text.lower():
                self.cursor, self.scroll = idx, max(0, idx - 3)
                self.status = f"jumped to L{line.line_number}"
                return
        self.status = f"no match for {needle[:30]!r}"

    def _goto_line(self, stdscr) -> None:
        val = self._ask(stdscr, "goto line: ")
        if val.isdigit():
            want = int(val)
            for idx, line in enumerate(self.lines):
                if line.line_number == want:
                    self.cursor, self.scroll = idx, max(0, idx - 3)
                    return

    # -- editor / input ---------------------------------------------------
    def _ask(self, stdscr, prompt: str) -> str:
        max_y, max_x = stdscr.getmaxyx()
        curses.echo()
        curses.curs_set(1)
        stdscr.addstr(max_y - 1, 0, " " * (max_x - 1))
        stdscr.addstr(max_y - 1, 0, prompt[: max_x - 2], curses.A_BOLD)
        try:
            return stdscr.getstr().decode("utf-8", "replace").strip()
        except Exception:
            return ""
        finally:
            curses.noecho()
            curses.curs_set(0)

    def _run_editor(self, stdscr, path: str) -> None:
        editor = os.environ.get("VISUAL") or os.environ.get("EDITOR") or "vi"
        curses.endwin()
        try:
            subprocess.call(f'{editor} "{path}"', shell=True)
        finally:
            stdscr.clear()
            curses.flushinp()
            stdscr.refresh()

    def _edit_file(self, stdscr, path: Optional[str]) -> None:
        if path:
            self._run_editor(stdscr, path)

    def _edit_text(self, stdscr, initial: str, name: str) -> str:
        fd, path = tempfile.mkstemp(suffix="-" + name)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(initial)
            self._run_editor(stdscr, path)
            with open(path, "r", encoding="utf-8") as fh:
                return fh.read().strip()
        finally:
            try:
                os.unlink(path)
            except OSError:
                pass

    # -- commit -----------------------------------------------------------
    def _commit(self, stdscr) -> None:
        if not self.exchange.prompt.strip() and not self.config["bare_commit"]:
            self.status = "prompt is empty (P to write one, b for a bare commit)"
            return
        self.exchange.meta["state"] = "closed"
        self.exchange.meta.setdefault("date", now_stamp())
        self.save_exchange()
        msg = self.commit_message()
        ans = self._ask(stdscr, f"commit {msg.splitlines()[0][:40]!r} ? [y/N] ")
        if ans.lower() not in ("y", "yes"):
            self.exchange.meta["state"] = "open"
            self.save_exchange()
            self.status = "cancelled"
            return
        ok, out = self.git.commit(msg)
        self.status = out if ok else f"failed: {out}"
        if ok:
            self.exchange = self.store.create(model=self.exchange.model, doc=self.doc_rel)

    # -- rendering --------------------------------------------------------
    def _draw_doc(self, stdscr, height: int, width: int) -> None:
        num = self.store.number_of(self.exchange) or 0
        branch = self.git.current_branch()
        tag, at_tag = self.git.tag_info()
        stale = " ⚠doc changed" if self.doc_is_stale() else ""
        header = (
            f" {os.path.basename(self.plan_path)} "
            f"L{self.lines[self.cursor].line_number if self.lines else 0} "
            f"│ {branch}→{self.git.default_branch()} "
            f"│ {num:04d} {self.exchange.state} "
            f"│ pending-push {tag or '-'}{'*' if at_tag else ''}{stale} "
        )
        stdscr.addstr(0, 0, header.ljust(width)[:width], curses.color_pair(WysiwygRenderer.COLOR_STATUS_BAR) | curses.A_BOLD)

        anchored = self.anchored_lines()
        lo, hi = self.selection()
        row = 1
        for idx in range(self.scroll, len(self.lines)):
            if row >= height:
                break
            line = self.lines[idx]
            selected = lo <= idx <= hi
            for text, attr, _ in WysiwygRenderer.format_line(
                line,
                wrap_width=min(self.wrap_width, width - 2),
                has_comment=line.line_number in anchored,
                is_selected=selected,
            ):
                if row >= height:
                    break
                body = text.ljust(width)[:width]
                if selected:
                    marker = "▶" if idx == self.cursor else "┃"
                    stdscr.addstr(row, 0, (marker + body[1:])[:width], curses.color_pair(WysiwygRenderer.COLOR_ACTIVE_LINE))
                else:
                    stdscr.addstr(row, 0, body, attr)
                row += 1

    def _pane_text(self) -> List[str]:
        tab = TABS[self.tab]
        if tab == "commit":
            return self.commit_message().splitlines()
        if tab == "prompt":
            return (self.exchange.compose_prompt() or "(empty — P to write)").splitlines()
        if tab == "response":
            return (self.exchange.response or "(empty — R pastes the clipboard)").splitlines()
        out: List[str] = []
        for a in self.exchange.anchors:
            out.append(a.header())
            out += [f"> {q}" for q in a.quote]
            out += a.comment.splitlines()
            out.append("")
        return out or ["(no anchors — c on a line)"]

    def _draw_pane(self, stdscr, height: int, x: int, width: int) -> None:
        for y in range(height):
            stdscr.addstr(y, x - 1, "│", curses.color_pair(WysiwygRenderer.COLOR_BORDER))
        labels = " ".join(
            f"{i + 1}·{name}" + ("◂" if i == self.tab else " ") for i, name in enumerate(TABS)
        )
        mode = "bare" if self.config["bare_commit"] else "full"
        stdscr.addstr(0, x, f" {labels} [{mode}] ".ljust(width)[:width], curses.color_pair(WysiwygRenderer.COLOR_STATUS_BAR) | curses.A_BOLD)

        body = self._pane_text()
        self.pane_scroll = max(0, min(self.pane_scroll, max(0, len(body) - 1)))
        row = 1
        import textwrap

        for raw in body[self.pane_scroll :]:
            for piece in textwrap.wrap(raw, width=width - 1) or [""]:
                if row >= height:
                    return
                if raw.startswith("@@"):
                    attr = curses.color_pair(WysiwygRenderer.COLOR_ALERT_IMPORTANT) | curses.A_BOLD
                elif raw.startswith(">"):
                    attr = curses.color_pair(WysiwygRenderer.COLOR_ALERT_NOTE)
                elif raw.split(":")[0] in ("Review-Doc", "Review-Log", "Reviewed-By", "Claude-Session", "Co-Authored-By"):
                    attr = curses.color_pair(WysiwygRenderer.COLOR_GUTTER)
                elif row == 1:
                    attr = curses.color_pair(WysiwygRenderer.COLOR_HEADING1) | curses.A_BOLD
                else:
                    attr = curses.color_pair(WysiwygRenderer.COLOR_DEFAULT)
                stdscr.addstr(row, x, piece.ljust(width)[:width], attr)
                row += 1

    def _draw_status(self, stdscr, y: int, width: int) -> None:
        try:
            stdscr.addstr(y, 0, f" {self.status} ".ljust(width)[: width - 1], curses.color_pair(WysiwygRenderer.COLOR_STATUS_BAR))
        except curses.error:
            pass

    def _help(self, stdscr) -> None:
        text = [
            "  Review Anchor",
            "  ─────────────────────────────────────────────────────────",
            "  j k ↑ ↓ PgUp PgDn g G   move        # goto line",
            "  v            toggle range mark (anchor several lines)",
            "  c / Enter    comment on the line or range (empty → $EDITOR)",
            "  d / x        drop anchors on the line or range",
            "  V            verify anchors, relocate ones the doc moved",
            "  p            paste from clipboard and jump to the match",
            "",
            "  P            edit the prompt in $EDITOR",
            "  r            edit the response in $EDITOR",
            "  R            replace the response from the clipboard",
            "  e            edit the whole exchange file in $EDITOR",
            "  y            copy prompt + anchors  (paste this to the model)",
            "  Y            copy the rendered commit message",
            "",
            "  m s          set model label / commit subject",
            "  b            toggle bare commit (subject only, pending-push)",
            "  n [ ]        new exchange / previous / next",
            "  C            git add -A && git commit",
            "",
            "  1 2 3 4      pane: commit · prompt · response · anchors",
            "  J K          scroll the pane      Tab  toggle split",
            "  + -          wrap width (match the IDE's line breaks)",
            "  ? q          this help / quit",
            "",
            "  No model API is called; prompts and responses move by clipboard.",
            "  Press any key.",
        ]
        max_y, max_x = stdscr.getmaxyx()
        h, w = min(len(text) + 2, max_y), min(max(len(l) for l in text) + 4, max_x)
        win = curses.newwin(h, w, max(0, (max_y - h) // 2), max(0, (max_x - w) // 2))
        win.box()
        for i, line in enumerate(text[: h - 2]):
            win.addstr(i + 1, 2, line[: w - 4], curses.A_BOLD if i < 2 else curses.A_NORMAL)
        win.refresh()
        win.getch()
