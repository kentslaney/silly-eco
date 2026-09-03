"""
WYSIWYG Markdown Renderer for Curses TUI.
Renders markdown elements with styling matching the Antigravity IDE review pane:
- Headings styled prominently
- GitHub Alerts ([!NOTE], [!IMPORTANT], [!TIP], etc.) styled with distinct colored borders
- Code blocks with distinct formatting
- Line numbers in gutter
- Comment badges [★ Review]
- Dynamic word wrapping with adjustable column width
"""

import curses
import textwrap
from typing import List, Tuple
from .markdown_parser import MarkdownLine


class WysiwygRenderer:
    # Color pair indices
    COLOR_DEFAULT = 1
    COLOR_GUTTER = 2
    COLOR_HEADING1 = 3
    COLOR_HEADING2 = 4
    COLOR_HEADING3 = 5
    COLOR_ALERT_NOTE = 6
    COLOR_ALERT_IMPORTANT = 7
    COLOR_ALERT_TIP = 8
    COLOR_ALERT_WARN = 9
    COLOR_ALERT_CAUTION = 10
    COLOR_CODE = 11
    COLOR_COMMENT_BADGE = 12
    COLOR_ACTIVE_LINE = 13
    COLOR_STATUS_BAR = 14
    COLOR_BORDER = 15

    @classmethod
    def init_colors(cls):
        if not curses.has_colors():
            return
        curses.start_color()
        curses.use_default_colors()

        # Pair definitions: (pair_id, fg, bg)
        curses.init_pair(cls.COLOR_DEFAULT, -1, -1)
        curses.init_pair(cls.COLOR_GUTTER, curses.COLOR_BLACK + 8 if curses.COLORS > 8 else curses.COLOR_WHITE, -1)
        curses.init_pair(cls.COLOR_HEADING1, curses.COLOR_CYAN, -1)
        curses.init_pair(cls.COLOR_HEADING2, curses.COLOR_BLUE, -1)
        curses.init_pair(cls.COLOR_HEADING3, curses.COLOR_MAGENTA, -1)

        curses.init_pair(cls.COLOR_ALERT_NOTE, curses.COLOR_CYAN, -1)
        curses.init_pair(cls.COLOR_ALERT_IMPORTANT, curses.COLOR_MAGENTA, -1)
        curses.init_pair(cls.COLOR_ALERT_TIP, curses.COLOR_GREEN, -1)
        curses.init_pair(cls.COLOR_ALERT_WARN, curses.COLOR_YELLOW, -1)
        curses.init_pair(cls.COLOR_ALERT_CAUTION, curses.COLOR_RED, -1)

        curses.init_pair(cls.COLOR_CODE, curses.COLOR_GREEN, -1)
        curses.init_pair(cls.COLOR_COMMENT_BADGE, curses.COLOR_YELLOW, curses.COLOR_BLUE)
        curses.init_pair(cls.COLOR_ACTIVE_LINE, curses.COLOR_WHITE, curses.COLOR_BLUE)
        curses.init_pair(cls.COLOR_STATUS_BAR, curses.COLOR_BLACK, curses.COLOR_WHITE)
        curses.init_pair(cls.COLOR_BORDER, curses.COLOR_CYAN, -1)

    @classmethod
    def get_alert_color(cls, alert_type: str) -> int:
        at = alert_type.upper()
        if at == "IMPORTANT":
            return curses.color_pair(cls.COLOR_ALERT_IMPORTANT) | curses.A_BOLD
        elif at == "TIP":
            return curses.color_pair(cls.COLOR_ALERT_TIP) | curses.A_BOLD
        elif at == "WARNING":
            return curses.color_pair(cls.COLOR_ALERT_WARN) | curses.A_BOLD
        elif at == "CAUTION":
            return curses.color_pair(cls.COLOR_ALERT_CAUTION) | curses.A_BOLD
        return curses.color_pair(cls.COLOR_ALERT_NOTE) | curses.A_BOLD

    @classmethod
    def format_line(
        cls,
        line: MarkdownLine,
        wrap_width: int,
        has_comment: bool,
        is_selected: bool,
        ref_id: int = None
    ) -> List[Tuple[str, int, int]]:
        """
        Returns a list of rendered visual rows: (text, attr, line_number).
        """
        rows: List[Tuple[str, int, int]] = []
        raw = line.raw_text
        gutter = f"{line.line_number:4d} │ "
        content_width = max(20, wrap_width - len(gutter) - 4)

        if has_comment:
            comment_tag = f" [★ Ref {ref_id}]" if ref_id is not None else " [★ Review]"
        else:
            comment_tag = ""

        if line.line_type == "heading":
            if line.heading_level == 1:
                title = f"# {raw.lstrip('#').strip()}" + comment_tag
                attr = curses.color_pair(cls.COLOR_HEADING1) | curses.A_BOLD | curses.A_UNDERLINE
            elif line.heading_level == 2:
                title = f"## {raw.lstrip('#').strip()}" + comment_tag
                attr = curses.color_pair(cls.COLOR_HEADING2) | curses.A_BOLD
            else:
                title = f"### {raw.lstrip('#').strip()}" + comment_tag
                attr = curses.color_pair(cls.COLOR_HEADING3) | curses.A_BOLD
            
            wrapped = textwrap.wrap(title, width=content_width) or [""]
            for i, w in enumerate(wrapped):
                g = gutter if i == 0 else "     │ "
                rows.append((g + w, attr, line.line_number))

        elif line.line_type == "alert":
            attr = cls.get_alert_color(line.alert_type)
            badge = f"│ [!{line.alert_type}] " if line.alert_type else "│ "
            body = (badge + line.alert_body + comment_tag).strip()
            wrapped = textwrap.wrap(body, width=content_width) or ["│"]
            for i, w in enumerate(wrapped):
                g = gutter if i == 0 else "     │ "
                rows.append((g + w, attr, line.line_number))

        elif line.line_type in ("code_fence", "code_body"):
            attr = curses.color_pair(cls.COLOR_CODE)
            text = ("  " + raw + comment_tag)
            rows.append((gutter + text[:content_width], attr, line.line_number))

        elif line.line_type == "horizontal_rule":
            attr = curses.color_pair(cls.COLOR_GUTTER)
            hr = "─" * min(content_width, 60)
            rows.append((gutter + hr, attr, line.line_number))

        elif line.line_type == "blank":
            attr = curses.color_pair(cls.COLOR_DEFAULT)
            rows.append((gutter, attr, line.line_number))

        else:
            attr = curses.color_pair(cls.COLOR_DEFAULT)
            text = raw + comment_tag
            wrapped = textwrap.wrap(text, width=content_width) or [""]
            for i, w in enumerate(wrapped):
                g = gutter if i == 0 else "     │ "
                rows.append((g + w, attr, line.line_number))

        return rows
