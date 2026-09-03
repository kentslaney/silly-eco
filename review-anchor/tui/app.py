"""
Interactive Curses TUI Application for Review Anchoring.
Provides side-by-side WYSIWYG markdown viewing, line-by-line comment anchoring,
configurable model names, and backwards-compatible git commit & 'pending-push' tag management.
"""

import curses
import os
import subprocess
from typing import List, Optional, Tuple
from .clipboard import Clipboard
from .git_anchoring import GitAnchoring, ReviewComment
from .markdown_parser import MarkdownLine, MarkdownParser
from .wysiwyg_renderer import WysiwygRenderer


class ReviewAnchorTUI:
    def __init__(self, plan_path: str, repo_root: Optional[str] = None):
        self.plan_path = plan_path
        self.repo_root = repo_root or os.getcwd()
        self.markdown_lines: List[MarkdownLine] = []
        self.git_anchor = GitAnchoring(repo_root=self.repo_root, plan_path=self.plan_path)
        
        # State
        self.selected_line_idx = 0
        self.scroll_offset = 0
        self.wrap_width = 80
        self.show_split_pane = True
        self.status_message = "Press 'c' to comment, 'm' for model, 't' toggle mode, 'G' commit, '?' for help"
        
        self.load_file()

    def load_file(self):
        if os.path.exists(self.plan_path):
            self.markdown_lines = MarkdownParser.parse_file(self.plan_path)
        else:
            self.markdown_lines = [
                MarkdownLine(line_number=1, raw_text=f"# File not found: {self.plan_path}", line_type="heading", heading_level=1)
            ]

    def _get_current_section(self) -> Tuple[str, str]:
        if not self.markdown_lines:
            return "", ""
        current_idx = min(self.selected_line_idx, len(self.markdown_lines) - 1)
        for idx in range(current_idx, -1, -1):
            line = self.markdown_lines[idx]
            if line.line_type == "heading":
                title = line.raw_text.lstrip("#").strip()
                return title, line.heading_slug
        return "", ""

    def run(self):
        curses.wrapper(self._main_loop)

    def _main_loop(self, stdscr):
        curses.curs_set(0)
        stdscr.clear()
        stdscr.keypad(True)
        WysiwygRenderer.init_colors()

        while True:
            max_y, max_x = stdscr.getmaxyx()
            stdscr.erase()

            if max_y < 10 or max_x < 40:
                stdscr.addstr(0, 0, "Terminal window too small.", curses.A_BOLD)
                stdscr.refresh()
                key = stdscr.getch()
                if key in (ord('q'), 27):
                    break
                continue

            # Determine split widths
            if self.show_split_pane and max_x >= 90:
                doc_width = max(45, int(max_x * 0.56))
                right_width = max_x - doc_width - 1
            else:
                doc_width = max_x
                right_width = 0

            # Render Document Pane
            self._render_document_pane(stdscr, max_y - 2, doc_width)

            # Render Right Split
            if right_width > 0:
                self._render_right_pane(stdscr, max_y - 2, doc_width + 1, right_width)

            # Render Status Bar
            self._render_status_bar(stdscr, max_y - 1, max_x)

            stdscr.refresh()

            try:
                key = stdscr.getch()
            except KeyboardInterrupt:
                break

            # Handle Keypresses
            if key in (ord('q'), 27):
                break
            elif key in (curses.KEY_UP, ord('k')):
                if self.selected_line_idx > 0:
                    self.selected_line_idx -= 1
                    if self.selected_line_idx < self.scroll_offset:
                        self.scroll_offset = self.selected_line_idx
            elif key in (curses.KEY_DOWN, ord('j')):
                if self.selected_line_idx < len(self.markdown_lines) - 1:
                    self.selected_line_idx += 1
                    visible_height = max_y - 4
                    if self.selected_line_idx >= self.scroll_offset + visible_height:
                        self.scroll_offset += 1
            elif key == curses.KEY_PPAGE:
                step = max(1, max_y - 4)
                self.selected_line_idx = max(0, self.selected_line_idx - step)
                self.scroll_offset = max(0, self.scroll_offset - step)
            elif key == curses.KEY_NPAGE:
                step = max(1, max_y - 4)
                self.selected_line_idx = min(len(self.markdown_lines) - 1, self.selected_line_idx + step)
                self.scroll_offset = min(max(0, len(self.markdown_lines) - step), self.scroll_offset + step)
            elif key in (ord('+'), ord('=')):
                self.wrap_width = min(140, self.wrap_width + 5)
                self.status_message = f"Adjusted wrap width to {self.wrap_width} cols"
            elif key in (ord('-'), ord('_')):
                self.wrap_width = max(40, self.wrap_width - 5)
                self.status_message = f"Adjusted wrap width to {self.wrap_width} cols"
            elif key in (ord('\t'), ord('s')):
                self.show_split_pane = not self.show_split_pane
            elif key in (ord('c'), ord('\n'), 10, 13):
                self._handle_add_comment(stdscr)
            elif key in (ord('d'), ord('x')):
                curr_line = self.markdown_lines[self.selected_line_idx].line_number
                self.git_anchor.remove_comments_for_line(curr_line)
                self.status_message = f"Cleared comments on line {curr_line}."
            elif key == ord('p'):
                self._handle_paste_search(stdscr)
            elif key == ord('m'):
                self._handle_configure_model(stdscr)
            elif key == ord('t'):
                self.git_anchor.commit_mode = "detailed" if self.git_anchor.commit_mode == "model_only" else "model_only"
                self.git_anchor.save_config()
                mode_desc = "Model Name Only (pending-push)" if self.git_anchor.commit_mode == "model_only" else "Detailed with Trailers"
                self.status_message = f"Switched commit mode to: {mode_desc}"
            elif key in (ord('y'), ord('Y')):
                msg = self.git_anchor.format_commit_message()
                if Clipboard.set_text(msg):
                    self.status_message = f"✓ Copied commit message [{self.git_anchor.commit_mode}] to macOS clipboard!"
                else:
                    self.status_message = "Failed to copy to clipboard."
            elif key in (ord('g'), ord('G')):
                self._handle_git_commit(stdscr)
            elif key == ord('?'):
                self._show_help_dialog(stdscr)

    def _render_document_pane(self, stdscr, max_y: int, width: int):
        cur_line_num = self.markdown_lines[self.selected_line_idx].line_number if self.markdown_lines else 1
        sec_name, _ = self._get_current_section()
        curr_branch = self.git_anchor.get_current_branch()
        def_branch = self.git_anchor.get_default_branch()
        tag_hash, is_at_tag = self.git_anchor.get_pending_push_info()

        bookmark_str = f"bookmark: {tag_hash}" if tag_hash else ""

        header = f" {os.path.basename(self.plan_path)} | L{cur_line_num} | {curr_branch}→{def_branch} | {bookmark_str} "
        stdscr.addstr(0, 0, header.ljust(width)[:width], curses.color_pair(WysiwygRenderer.COLOR_STATUS_BAR) | curses.A_BOLD)

        row_y = 1
        for idx in range(self.scroll_offset, len(self.markdown_lines)):
            if row_y >= max_y:
                break
            mline = self.markdown_lines[idx]
            is_selected = (idx == self.selected_line_idx)
            has_comment = (mline.line_number in self.git_anchor.comments)

            rendered_rows = WysiwygRenderer.format_line(
                mline,
                wrap_width=min(self.wrap_width, width - 2),
                has_comment=has_comment,
                is_selected=is_selected
            )

            for text, attr, lnum in rendered_rows:
                if row_y >= max_y:
                    break
                line_display = text.ljust(width)[:width]
                if is_selected:
                    line_display = "▶ " + line_display[2:]
                    stdscr.addstr(row_y, 0, line_display, curses.color_pair(WysiwygRenderer.COLOR_ACTIVE_LINE) | curses.A_BOLD)
                else:
                    stdscr.addstr(row_y, 0, line_display, attr)
                row_y += 1

    def _render_right_pane(self, stdscr, max_y: int, start_x: int, width: int):
        for y in range(max_y):
            stdscr.addstr(y, start_x - 1, "│", curses.color_pair(WysiwygRenderer.COLOR_BORDER))

        mode_badge = "[MODEL-ONLY: pending-push]" if self.git_anchor.commit_mode == "model_only" else "[DETAILED + NOTES]"
        title = f" COMMIT & REVIEW ({mode_badge}) "
        stdscr.addstr(0, start_x, title.ljust(width)[:width], curses.color_pair(WysiwygRenderer.COLOR_STATUS_BAR) | curses.A_BOLD)

        commit_msg = self.git_anchor.format_commit_message()
        lines = commit_msg.splitlines()

        row_y = 1
        for line in lines:
            if row_y >= max_y - 4:
                break
            if line.startswith("gemini") or line.startswith("Review-"):
                attr = curses.color_pair(WysiwygRenderer.COLOR_HEADING1) | curses.A_BOLD
            elif line.startswith("[Line"):
                attr = curses.color_pair(WysiwygRenderer.COLOR_ALERT_IMPORTANT) | curses.A_BOLD
            elif line.startswith("> "):
                attr = curses.color_pair(WysiwygRenderer.COLOR_ALERT_NOTE)
            else:
                attr = curses.color_pair(WysiwygRenderer.COLOR_DEFAULT)

            stdscr.addstr(row_y, start_x, line.ljust(width)[:width], attr)
            row_y += 1

        # Show Git Notes preview if in model_only mode and comments exist
        if self.git_anchor.commit_mode == "model_only" and self.git_anchor.comments:
            notes_hdr = "── Git Notes (Attached to Commit) ──"
            stdscr.addstr(row_y, start_x, notes_hdr[:width], curses.color_pair(WysiwygRenderer.COLOR_BORDER))
            row_y += 1
            for n_line in self.git_anchor.format_review_body().splitlines():
                if row_y >= max_y:
                    break
                stdscr.addstr(row_y, start_x, n_line.ljust(width)[:width], curses.color_pair(WysiwygRenderer.COLOR_GUTTER))
                row_y += 1

    def _render_status_bar(self, stdscr, y: int, width: int):
        bar = f" {self.status_message} "
        stdscr.addstr(y, 0, bar.ljust(width)[:width], curses.color_pair(WysiwygRenderer.COLOR_STATUS_BAR))

    def _handle_configure_model(self, stdscr):
        prompt_str = f"Set Model Name (current: '{self.git_anchor.model_header}'): "
        curses.echo()
        curses.curs_set(1)

        max_y, max_x = stdscr.getmaxyx()
        stdscr.addstr(max_y - 1, 0, " " * max_x)
        stdscr.addstr(max_y - 1, 0, prompt_str[:max_x - 1], curses.A_BOLD)

        try:
            inp = stdscr.getstr(max_y - 1, min(len(prompt_str), max_x - 5)).decode("utf-8").strip()
        except Exception:
            inp = ""
        finally:
            curses.noecho()
            curses.curs_set(0)

        if inp:
            self.git_anchor.model_header = inp
            self.git_anchor.save_config()
            self.status_message = f"✓ Configured model name: '{inp}'"
        else:
            self.status_message = "Model name unchanged."

    def _handle_add_comment(self, stdscr):
        curr_line = self.markdown_lines[self.selected_line_idx]
        sec_name, sec_slug = self._get_current_section()

        prompt_str = f"Comment for L{curr_line.line_number} (Enter to paste clipboard): "
        curses.echo()
        curses.curs_set(1)

        max_y, max_x = stdscr.getmaxyx()
        stdscr.addstr(max_y - 1, 0, " " * max_x)
        stdscr.addstr(max_y - 1, 0, prompt_str[:max_x - 1], curses.A_BOLD)

        try:
            inp = stdscr.getstr(max_y - 1, min(len(prompt_str), max_x - 5)).decode("utf-8").strip()
        except Exception:
            inp = ""
        finally:
            curses.noecho()
            curses.curs_set(0)

        if not inp:
            clip = Clipboard.get_text().strip()
            if clip:
                inp = clip

        if inp:
            self.git_anchor.add_comment(
                line=curr_line,
                comment_text=inp,
                section_name=sec_name,
                section_slug=sec_slug
            )
            self.status_message = f"✓ Added comment to Line {curr_line.line_number}!"
        else:
            self.status_message = "Comment cancelled."

    def _handle_paste_search(self, stdscr):
        clip = Clipboard.get_text().strip()
        if not clip:
            self.status_message = "Clipboard is empty."
            return

        target_line = None
        cleaned_clip = clip.lower()

        if clip.isdigit():
            target_num = int(clip)
            for idx, mline in enumerate(self.markdown_lines):
                if mline.line_number == target_num:
                    target_line = idx
                    break
        else:
            for idx, mline in enumerate(self.markdown_lines):
                if cleaned_clip in mline.raw_text.lower():
                    target_line = idx
                    break

        if target_line is not None:
            self.selected_line_idx = target_line
            self.scroll_offset = max(0, target_line - 3)
            self.status_message = f"Jumped to line matching: '{clip[:25]}...'"
        else:
            self.status_message = f"No match for: '{clip[:25]}...'"

    def _handle_git_commit(self, stdscr):
        msg = self.git_anchor.format_commit_message()
        mode_desc = "Temporary / Model-Only" if self.git_anchor.commit_mode == "model_only" else "Detailed Review"
        confirm_str = f"Create git commit [{mode_desc}] with message '{msg[:30]}'? (y/n): "

        max_y, max_x = stdscr.getmaxyx()
        stdscr.addstr(max_y - 1, 0, " " * max_x)
        stdscr.addstr(max_y - 1, 0, confirm_str[:max_x - 1], curses.A_BOLD)
        ch = stdscr.getch()

        if ch in (ord('y'), ord('Y')):
            ok, result = self.git_anchor.execute_commit()
            self.status_message = result
        else:
            self.status_message = "Cancelled."

    def _show_help_dialog(self, stdscr):
        max_y, max_x = stdscr.getmaxyx()
        help_lines = [
            "  Review Anchor - Help & Keybindings",
            "──────────────────────────────────────────────",
            "  j / ↓         : Move down 1 line",
            "  k / ↑         : Move up 1 line",
            "  PgDn / PgUp   : Page down / Page up",
            "  c / Enter     : Add/edit review comment for selected line",
            "  d / x         : Delete comment on selected line",
            "  p             : Paste from clipboard & jump to matching text",
            "  m             : Configure model name (e.g. 'gemini 3.8 flash high')",
            "  t             : Toggle commit mode ('model_only' vs 'detailed')",
            "  + / -         : Adjust column wrap width (match IDE line breaks)",
            "  Tab / s       : Toggle side-by-side split pane",
            "  y             : Copy formatted commit message to clipboard",
            "  G             : Run git commit",
            "  ?             : Show this help window",
            "  q / Esc       : Quit",
            "",
            "  Bookmark Note:",
            "  'pending-push' is preserved as an immutable example bookmark.",
            "",
            "Press any key to close help."
        ]

        box_h = len(help_lines) + 2
        box_w = max(len(l) for l in help_lines) + 4
        start_y = max(1, (max_y - box_h) // 2)
        start_x = max(1, (max_x - box_w) // 2)

        win = curses.newwin(box_h, box_w, start_y, start_x)
        win.box()
        for idx, l in enumerate(help_lines):
            win.addstr(idx + 1, 2, l[:box_w - 4], curses.A_BOLD if idx < 2 else curses.A_NORMAL)
        win.refresh()
        win.getch()
