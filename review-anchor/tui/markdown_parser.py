"""
Markdown parser for Review Anchor.
Parses markdown files into structured line objects with line numbers,
syntactic types (headings, alerts, code blocks, lists, quotes), and anchor slugs.
"""

from dataclasses import dataclass, field
import re
from typing import List, Optional


@dataclass
class MarkdownLine:
    line_number: int  # 1-indexed
    raw_text: str
    line_type: str  # 'heading', 'alert', 'code_fence', 'code_body', 'blockquote', 'list_item', 'horizontal_rule', 'text', 'blank'
    heading_level: int = 0
    heading_slug: str = ""
    alert_type: str = ""  # 'NOTE', 'TIP', 'IMPORTANT', 'WARNING', 'CAUTION'
    alert_body: str = ""
    is_in_code_block: bool = False
    indent_level: int = 0
    comments: List[str] = field(default_factory=list)


class MarkdownParser:
    ALERT_PATTERN = re.compile(r"^>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*(.*)$", re.IGNORECASE)
    HEADING_PATTERN = re.compile(r"^(#{1,6})\s+(.+)$")
    LIST_PATTERN = re.compile(r"^(\s*)([-*+]|\d+\.)\s+(.+)$")
    HR_PATTERN = re.compile(r"^\s*([-*_]){3,}\s*$")

    @classmethod
    def slugify(cls, text: str) -> str:
        """Create URL / anchor slug from heading text."""
        cleaned = re.sub(r"[^\w\s-]", "", text.lower())
        return re.sub(r"[-\s]+", "-", cleaned).strip("-")

    @classmethod
    def parse_text(cls, content: str) -> List[MarkdownLine]:
        raw_lines = content.splitlines()
        parsed: List[MarkdownLine] = []
        in_code_block = False
        current_alert_type: Optional[str] = None

        for idx, raw in enumerate(raw_lines):
            line_num = idx + 1
            stripped = raw.strip()

            # Handle code block fence
            if stripped.startswith("```") or stripped.startswith("~~~"):
                in_code_block = not in_code_block
                current_alert_type = None
                parsed.append(MarkdownLine(
                    line_number=line_num,
                    raw_text=raw,
                    line_type="code_fence",
                    is_in_code_block=in_code_block
                ))
                continue

            if in_code_block:
                parsed.append(MarkdownLine(
                    line_number=line_num,
                    raw_text=raw,
                    line_type="code_body",
                    is_in_code_block=True
                ))
                continue

            # Blank line
            if not stripped:
                current_alert_type = None
                parsed.append(MarkdownLine(
                    line_number=line_num,
                    raw_text=raw,
                    line_type="blank"
                ))
                continue

            # Alert header
            alert_match = cls.ALERT_PATTERN.match(stripped)
            if alert_match:
                current_alert_type = alert_match.group(1).upper()
                remaining = alert_match.group(2).strip()
                parsed.append(MarkdownLine(
                    line_number=line_num,
                    raw_text=raw,
                    line_type="alert",
                    alert_type=current_alert_type,
                    alert_body=remaining
                ))
                continue

            # Continuing blockquote / alert body
            if stripped.startswith(">"):
                body = stripped.lstrip(">").strip()
                parsed.append(MarkdownLine(
                    line_number=line_num,
                    raw_text=raw,
                    line_type="alert" if current_alert_type else "blockquote",
                    alert_type=current_alert_type or "",
                    alert_body=body
                ))
                continue
            else:
                current_alert_type = None

            # Headings
            heading_match = cls.HEADING_PATTERN.match(stripped)
            if heading_match:
                level = len(heading_match.group(1))
                title = heading_match.group(2).strip()
                slug = cls.slugify(title)
                parsed.append(MarkdownLine(
                    line_number=line_num,
                    raw_text=raw,
                    line_type="heading",
                    heading_level=level,
                    heading_slug=slug
                ))
                continue

            # Horizontal rule
            if cls.HR_PATTERN.match(stripped):
                parsed.append(MarkdownLine(
                    line_number=line_num,
                    raw_text=raw,
                    line_type="horizontal_rule"
                ))
                continue

            # List item
            list_match = cls.LIST_PATTERN.match(raw)
            if list_match:
                indent = len(list_match.group(1))
                parsed.append(MarkdownLine(
                    line_number=line_num,
                    raw_text=raw,
                    line_type="list_item",
                    indent_level=indent
                ))
                continue

            # Regular text
            parsed.append(MarkdownLine(
                line_number=line_num,
                raw_text=raw,
                line_type="text"
            ))

        return parsed

    @classmethod
    def parse_file(cls, filepath: str) -> List[MarkdownLine]:
        with open(filepath, "r", encoding="utf-8") as f:
            return cls.parse_text(f.read())
