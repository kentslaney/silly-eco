"""
Git Anchoring and Commit Formatter.
Maintains 100% backwards compatibility with the existing commit scheme:
- Model-Only Mode (matching 'pending-push' tag on staging): Commit message is JUST the configurable model name (e.g. 'gemini 3.8 flash high').
- Detailed Mode: Subject is the model name, body is the user prompt / review comments, with RFC 822 trailers.
Integrates branch awareness (default: 'staging'), 'pending-push' tag inspection, and Git Notes for review posterity.
"""

from dataclasses import dataclass, field
from datetime import datetime, timezone
import json
import os
import re
import subprocess
from typing import Dict, List, Optional, Tuple
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
    DEFAULT_MODEL = "gemini 3.8 flash high"
    DEFAULT_BRANCH = "staging"

    def __init__(self, repo_root: Optional[str] = None, plan_path: str = "implementation_plan.md"):
        self.repo_root = repo_root or self._find_repo_root()
        self.plan_path = plan_path
        self.model_header = self._detect_commit_scheme()
        self.commit_mode = "model_only"  # 'model_only' (pending-push style) or 'detailed'
        self.target_branch = self.DEFAULT_BRANCH
        self.author_name = self._detect_git_author()
        self.comments: Dict[int, List[ReviewComment]] = {}
        
        self.load_config()
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
        """Detect model name from 'pending-push' tag or latest commits."""
        try:
            # 1. Check pending-push commit message
            res_tag = subprocess.run(
                ["git", "log", "-n", "1", "--pretty=format:%s", "pending-push"],
                cwd=self.repo_root,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False
            )
            if res_tag.returncode == 0 and res_tag.stdout.strip():
                return res_tag.stdout.strip()

            # 2. Check recent commit subjects
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
        return self.DEFAULT_MODEL

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

    # Git Inspection
    def get_current_branch(self) -> str:
        try:
            res = subprocess.run(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                cwd=self.repo_root,
                stdout=subprocess.PIPE,
                text=True,
                check=False
            )
            if res.returncode == 0:
                return res.stdout.strip()
        except Exception:
            pass
        return "unknown"

    def get_default_branch(self) -> str:
        try:
            res = subprocess.run(
                ["git", "symbolic-ref", "refs/remotes/origin/HEAD"],
                cwd=self.repo_root,
                stdout=subprocess.PIPE,
                text=True,
                check=False
            )
            if res.returncode == 0:
                full_ref = res.stdout.strip()
                return full_ref.replace("refs/remotes/origin/", "")
        except Exception:
            pass
        return self.DEFAULT_BRANCH

    def get_pending_push_info(self) -> Tuple[Optional[str], bool]:
        """Returns (pending_push_short_hash, is_head_equal_to_pending_push)."""
        try:
            res_tag = subprocess.run(
                ["git", "rev-parse", "--short", "pending-push"],
                cwd=self.repo_root,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False
            )
            if res_tag.returncode != 0:
                return None, False

            tag_hash = res_tag.stdout.strip()
            res_head = subprocess.run(
                ["git", "rev-parse", "--short", "HEAD"],
                cwd=self.repo_root,
                stdout=subprocess.PIPE,
                text=True,
                check=False
            )
            head_hash = res_head.stdout.strip() if res_head.returncode == 0 else ""
            return tag_hash, (tag_hash == head_hash)
        except Exception:
            return None, False

    # Comments Management
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

    # Formatting
    def format_commit_message(self, general_prompt: Optional[str] = None, mode: Optional[str] = None) -> str:
        """
        Formats commit message according to active mode:
        - 'model_only': JUST the configurable model name (e.g. 'gemini 3.8 flash high')
        - 'detailed': model name + prompt + line anchors + RFC 822 trailers
        """
        active_mode = mode or self.commit_mode
        header = self.model_header.strip()

        if active_mode == "model_only":
            return header

        # Detailed mode
        body_parts: List[str] = []
        if general_prompt and general_prompt.strip():
            body_parts.append(general_prompt.strip())

        all_comments = self.get_comments()
        if all_comments:
            body_parts.append(self.format_review_body())

        if not body_parts:
            return header

        return f"{header}\n\n" + "\n\n".join(body_parts)

    def format_review_body(self) -> str:
        """Formats the review comments block and RFC 822 trailers."""
        all_comments = self.get_comments()
        if not all_comments:
            return ""

        rel_plan = os.path.basename(self.plan_path)
        blocks = [f"Reviewed {rel_plan}:"]

        for c in all_comments:
            sec_info = f" Section: \"{c.section_name}\"" if c.section_name else ""
            snippet = f"> \"{c.line_text}\"" if c.line_text else ""
            entry = f"[Line {c.line_number}]{sec_info}\n{snippet}\nReview: {c.comment_text}".strip()
            blocks.append(entry)

        # Trailers (RFC 822 format)
        trailers = [
            f"Review-Doc: {rel_plan}",
            f"Review-Anchor: #{all_comments[0].section_slug or f'L{all_comments[0].line_number}'}"
        ]
        if self.author_name:
            trailers.append(f"Reviewed-By: {self.author_name}")
        trailers.append(f"Reviewed-At: {datetime.now(timezone.utc).astimezone().isoformat()}")

        return "\n\n".join(blocks) + "\n\n" + "\n".join(trailers)

    # Tagging & Commits
    def tag_pending_push(self, commit_ref: str = "HEAD") -> Tuple[bool, str]:
        """Tags commit_ref with 'pending-push'."""
        try:
            res = subprocess.run(
                ["git", "tag", "-f", "pending-push", commit_ref],
                cwd=self.repo_root,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False
            )
            if res.returncode == 0:
                return True, f"Successfully tagged {commit_ref} as 'pending-push'"
            return False, res.stderr.strip()
        except Exception as e:
            return False, str(e)

    def execute_commit(
        self,
        general_prompt: Optional[str] = None,
        mode: Optional[str] = None,
        tag_pending: bool = False
    ) -> Tuple[bool, str]:
        """
        Runs git commit using the formatted message.
        If mode == 'model_only' and there are review comments, records them to Git Notes.
        If tag_pending == True, updates 'pending-push' tag to new HEAD.
        """
        active_mode = mode or self.commit_mode
        msg = self.format_commit_message(general_prompt=general_prompt, mode=active_mode)

        try:
            res = subprocess.run(
                ["git", "commit", "-m", msg],
                cwd=self.repo_root,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False
            )
            if res.returncode != 0:
                return False, f"Git commit failed: {res.stderr.strip()}"

            # Attach review comments to Git Notes if in model_only mode
            review_body = self.format_review_body()
            if active_mode == "model_only" and review_body:
                subprocess.run(
                    ["git", "notes", "add", "-f", "-m", review_body, "HEAD"],
                    cwd=self.repo_root,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=False
                )

            # Optionally tag as pending-push
            if tag_pending:
                self.tag_pending_push("HEAD")

            return True, "✓ Commit created successfully!"
        except Exception as e:
            return False, str(e)

    # Persistence
    def _config_path(self) -> str:
        return os.path.join(self.repo_root, ".review_config.json")

    def _persisted_path(self) -> str:
        return os.path.join(self.repo_root, ".review_anchors.json")

    def save_config(self):
        try:
            cfg = {
                "model_name": self.model_header,
                "commit_mode": self.commit_mode,
                "target_branch": self.target_branch
            }
            with open(self._config_path(), "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=2)
        except Exception:
            pass

    def load_config(self):
        path = self._config_path()
        if not os.path.exists(path):
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            if "model_name" in cfg and cfg["model_name"]:
                self.model_header = cfg["model_name"]
            if "commit_mode" in cfg and cfg["commit_mode"] in ("model_only", "detailed"):
                self.commit_mode = cfg["commit_mode"]
            if "target_branch" in cfg and cfg["target_branch"]:
                self.target_branch = cfg["target_branch"]
        except Exception:
            pass

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
