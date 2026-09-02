"""
Git Anchoring and Commit Formatter.
Maintains 100% backwards compatibility with the existing commit scheme:
Subject: <Model name or short summary, e.g. 'gemini 3.8 flash high'>
Body: <User prompt / review comment>
Footers: Review anchors, line ranges, and metadata trailers.
"""

from dataclasses import dataclass, field
from datetime import datetime, timezone
import json
import os
import re
import subprocess
from typing import Dict, List, Optional
from .markdown_parser import MarkdownLine


@dataclass
class ReviewComment:
    line_number: int
    line_text: str
    section_name: str
    section_slug: str
    comment_text: str
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).astimezone().isoformat())
    author: str = ""


class GitAnchoring:
    DEFAULT_MODEL_HEADER = "gemini 3.8 flash high"

    def __init__(self, repo_root: Optional[str] = None, plan_path: str = "implementation_plan.md"):
        self.repo_root = repo_root or self._find_repo_root()
        self.plan_path = plan_path
        self.model_header = self._detect_commit_scheme()
        self.author_name = self._detect_git_author()
        self.comments: Dict[int, List[ReviewComment]] = {}
        self.load_persisted_comments()

    def _find_repo_root(self) -> str:
        try:
            res = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False
            )
            if res.returncode == 0 and res.stdout.strip():
                return res.stdout.strip()
        except Exception:
            pass
        return os.getcwd()

    def _detect_commit_scheme(self) -> str:
        """Detect the subject line style from the most recent git commits."""
        try:
            res = subprocess.run(
                ["git", "log", "-n", "5", "--pretty=format:%s"],
                cwd=self.repo_root,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False
            )
            if res.returncode == 0:
                lines = [l.strip() for l in res.stdout.splitlines() if l.strip()]
                for line in lines:
                    if "gemini" in line.lower():
                        return line
        except Exception:
            pass
        return self.DEFAULT_MODEL_HEADER

    def _detect_git_author(self) -> str:
        """Detect author name and email from git config."""
        try:
            name = subprocess.run(["git", "config", "user.name"], stdout=subprocess.PIPE, text=True, check=False).stdout.strip()
            email = subprocess.run(["git", "config", "user.email"], stdout=subprocess.PIPE, text=True, check=False).stdout.strip()
            if name and email:
                return f"{name} <{email}>"
            elif name:
                return name
        except Exception:
            pass
        return "Reviewer"

    def add_comment(self, line: MarkdownLine, comment_text: str, section_name: str = "", section_slug: str = ""):
        if not comment_text.strip():
            return
        rc = ReviewComment(
            line_number=line.line_number,
            line_text=line.raw_text.strip(),
            section_name=section_name,
            section_slug=section_slug,
            comment_text=comment_text.strip(),
            author=self.author_name
        )
        if line.line_number not in self.comments:
            self.comments[line.line_number] = []
        self.comments[line.line_number].append(rc)
        self.save_persisted_comments()

    def remove_comments_for_line(self, line_number: int):
        if line_number in self.comments:
            del self.comments[line_number]
            self.save_persisted_comments()

    def get_comments(self) -> List[ReviewComment]:
        all_comments = []
        for lnum in sorted(self.comments.keys()):
            all_comments.extend(self.comments[lnum])
        return all_comments

    def format_commit_message(self, general_prompt: Optional[str] = None) -> str:
        """
        Builds a commit message that matches the existing scheme:
        Header: model tag (e.g. 'gemini 3.8 flash high')
        Body: User prompt/comments
        Anchors: Line references, snippets, and review trailers.
        """
        header = self.model_header.strip()
        body_parts: List[str] = []

        if general_prompt and general_prompt.strip():
            body_parts.append(general_prompt.strip())

        all_comments = self.get_comments()
        if all_comments:
            review_lines = []
            rel_plan = os.path.basename(self.plan_path)
            review_lines.append(f"Reviewed {rel_plan}:")

            for c in all_comments:
                sec_info = f" Section: \"{c.section_name}\"" if c.section_name else ""
                snippet = f"> \"{c.line_text}\"" if c.line_text else ""
                entry = f"[Line {c.line_number}]{sec_info}\n{snippet}\nReview: {c.comment_text}".strip()
                review_lines.append(entry)

            body_parts.append("\n\n".join(review_lines))

            # Trailers (RFC 822 format)
            trailers = []
            trailers.append(f"Review-Doc: {os.path.basename(self.plan_path)}")
            primary_slug = all_comments[0].section_slug if all_comments[0].section_slug else f"L{all_comments[0].line_number}"
            trailers.append(f"Review-Anchor: #{primary_slug}")
            if self.author_name:
                trailers.append(f"Reviewed-By: {self.author_name}")
            trailers.append(f"Reviewed-At: {datetime.now(timezone.utc).astimezone().isoformat()}")
            body_parts.append("\n".join(trailers))

        if not body_parts:
            return header

        return f"{header}\n\n" + "\n\n".join(body_parts)

    def _persisted_path(self) -> str:
        return os.path.join(self.repo_root, ".review_anchors.json")

    def save_persisted_comments(self):
        try:
            data = []
            for c in self.get_comments():
                data.append({
                    "line_number": c.line_number,
                    "line_text": c.line_text,
                    "section_name": c.section_name,
                    "section_slug": c.section_slug,
                    "comment_text": c.comment_text,
                    "timestamp": c.timestamp,
                    "author": c.author
                })
            with open(self._persisted_path(), "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
        except Exception:
            pass

    def load_persisted_comments(self):
        path = self._persisted_path()
        if not os.path.exists(path):
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.comments.clear()
            for item in data:
                rc = ReviewComment(
                    line_number=item["line_number"],
                    line_text=item.get("line_text", ""),
                    section_name=item.get("section_name", ""),
                    section_slug=item.get("section_slug", ""),
                    comment_text=item.get("comment_text", ""),
                    timestamp=item.get("timestamp", ""),
                    author=item.get("author", "")
                )
                if rc.line_number not in self.comments:
                    self.comments[rc.line_number] = []
                self.comments[rc.line_number].append(rc)
        except Exception:
            pass
