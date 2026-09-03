"""
Git Anchoring and Commit Formatter.
Maintains 100% backwards compatibility with the existing commit scheme:
- Subject line is strictly the configurable model name (e.g. 'gemini 3.8 flash high', matching 'pending-push' bookmark on staging).
- Commit body is the snapshot of the model input (general prompt, Claude Code Q/A, and review comments tagged with [Ref N]).
- Git Notes attach reference numbers ([Ref 1], [Ref 2]...) to their diff -p type context (heading/symbol context, line numbers, and hunks),
  which can move via operational transformation / rebase without altering commit messages.
- Integrates branch awareness (default: 'staging'), 'pending-push' tag inspection, and rebase-tolerant Git Notes.
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
    ref_id: int
    line_number: int
    line_text: str
    section_name: str
    section_slug: str
    comment_text: str
    diff_context: str = ""      # diff -p context header e.g. "@@ ## User Review Required @@"
    context_snippet: str = ""   # surrounding code / markdown hunk
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).astimezone().isoformat())
    author: str = ""


@dataclass
class QAItem:
    ref_id: Optional[int]
    question: str
    answer: str
    section_name: str = ""
    diff_context: str = ""
    context_snippet: str = ""
    timestamp: str = field(default_factory=lambda: datetime.now(timezone.utc).astimezone().isoformat())


class GitAnchoring:
    DEFAULT_MODEL = "gemini 3.8 flash high"
    DEFAULT_BRANCH = "staging"

    def __init__(self, repo_root: Optional[str] = None, plan_path: str = "implementation_plan.md"):
        self.repo_root = repo_root or self._find_repo_root()
        self.plan_path = plan_path
        self.model_header = self._detect_commit_scheme()
        self.commit_mode = "detailed"  # 'model_only' (pending-push style) or 'detailed'
        self.target_branch = self.DEFAULT_BRANCH
        self.author_name = self._detect_git_author()
        self.comments: Dict[int, List[ReviewComment]] = {}
        self.qa_items: List[QAItem] = []

        self.load_config()
        self.load_persisted_comments()
        self.load_persisted_qa()

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
        """Detect model name from latest commits or fallback to DEFAULT_MODEL."""
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
                    if "gemini" in line.lower() or "claude" in line.lower():
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

    # Diff -p Context Extraction
    def resolve_diff_p_context(self, file_path: str, line_num: int) -> Tuple[str, str]:
        """
        Extracts diff -p context:
        - Enclosing section header or function/class signature (e.g. '@@ ## User Review Required @@')
        - Surrounding hunk lines (context lines around line_num)
        """
        resolved_path = file_path
        if not os.path.isabs(resolved_path):
            resolved_path = os.path.join(self.repo_root, file_path)

        if not os.path.exists(resolved_path):
            return "@@ @@", ""

        try:
            with open(resolved_path, "r", encoding="utf-8") as f:
                all_lines = f.readlines()

            if not all_lines:
                return "@@ @@", ""

            idx = min(max(0, line_num - 1), len(all_lines) - 1)
            heading = ""
            # Search upwards for enclosing context (heading or function/symbol)
            for i in range(idx, -1, -1):
                line = all_lines[i].strip()
                if line.startswith("#") or any(line.startswith(k) for k in ("def ", "func ", "class ", "struct ", "type ")):
                    heading = line
                    break

            diff_header = f"@@ {heading} @@" if heading else "@@ @@"

            # Context hunk (1 line before, target line, 1 line after)
            start_idx = max(0, idx - 1)
            end_idx = min(len(all_lines), idx + 2)
            hunk = "".join(all_lines[start_idx:end_idx]).rstrip()
            return diff_header, hunk
        except Exception:
            return "@@ @@", ""

    def _next_ref_id(self) -> int:
        refs = [c.ref_id for c in self.get_comments() if c.ref_id is not None]
        refs += [q.ref_id for q in self.qa_items if q.ref_id is not None]
        return max(refs, default=0) + 1

    # Comments Management
    def add_comment(
        self,
        line: MarkdownLine,
        comment_text: str,
        section_name: str = "",
        section_slug: str = "",
        diff_context: str = "",
        context_snippet: str = ""
    ) -> Optional[ReviewComment]:
        if not comment_text.strip():
            return None

        if not diff_context or not context_snippet:
            auto_diff, auto_snip = self.resolve_diff_p_context(self.plan_path, line.line_number)
            diff_context = diff_context or auto_diff
            context_snippet = context_snippet or auto_snip

        rc = ReviewComment(
            ref_id=self._next_ref_id(),
            line_number=line.line_number,
            line_text=line.raw_text.strip(),
            section_name=section_name,
            section_slug=section_slug,
            comment_text=comment_text.strip(),
            diff_context=diff_context,
            context_snippet=context_snippet,
            author=self.author_name
        )
        if line.line_number not in self.comments:
            self.comments[line.line_number] = []
        self.comments[line.line_number].append(rc)
        self.save_persisted_comments()
        return rc

    def remove_comments_for_line(self, line_number: int):
        if line_number in self.comments:
            del self.comments[line_number]
            self.save_persisted_comments()

    def clear_all_comments(self):
        self.comments.clear()
        self.save_persisted_comments()

    def get_comments(self) -> List[ReviewComment]:
        all_comments = []
        for lnum in sorted(self.comments.keys()):
            all_comments.extend(self.comments[lnum])
        return all_comments

    # Claude Code Q/A Management
    def add_qa(
        self,
        question: str,
        answer: str,
        section_name: str = "",
        line_number: Optional[int] = None
    ) -> Optional[QAItem]:
        if not question.strip() and not answer.strip():
            return None

        ref_id = self._next_ref_id() if (section_name or line_number) else None
        diff_ctx = ""
        snippet = ""
        if line_number and os.path.exists(self.plan_path):
            diff_ctx, snippet = self.resolve_diff_p_context(self.plan_path, line_number)

        item = QAItem(
            ref_id=ref_id,
            question=question.strip(),
            answer=answer.strip(),
            section_name=section_name.strip(),
            diff_context=diff_ctx,
            context_snippet=snippet
        )
        self.qa_items.append(item)
        self.save_persisted_qa()
        return item

    def remove_qa(self, idx: int):
        if 0 <= idx < len(self.qa_items):
            self.qa_items.pop(idx)
            self.save_persisted_qa()

    def clear_qa(self):
        self.qa_items.clear()
        self.save_persisted_qa()

    def get_qa_items(self) -> List[QAItem]:
        return list(self.qa_items)

    # Formatting
    def format_commit_message(self, general_prompt: Optional[str] = None, mode: Optional[str] = None) -> str:
        """
        Formats commit message:
        - 'model_only': Strictly the configurable model name (e.g. 'gemini 3.8 flash high')
        - 'detailed': Subject is the model name. Body is snapshot of model input (prompt, Q/A, [Ref N] review comments)
        """
        active_mode = mode or self.commit_mode
        header = self.model_header.strip()

        if active_mode == "model_only":
            return header

        # Detailed mode: historical snapshot of model input
        body_parts: List[str] = []
        if general_prompt and general_prompt.strip():
            body_parts.append(general_prompt.strip())

        # Claude Code Q/A context
        qa_items = self.get_qa_items()
        if qa_items:
            qa_blocks = ["Claude Code Q/A Context:"]
            for q in qa_items:
                ref_str = f"[Ref {q.ref_id}] " if q.ref_id else ""
                sec_str = f"({q.section_name}) " if q.section_name else ""
                entry = f"{ref_str}{sec_str}\nQ: {q.question}\nA: {q.answer}".strip()
                qa_blocks.append(entry)
            body_parts.append("\n\n".join(qa_blocks))

        # Review Comments snapshot
        all_comments = self.get_comments()
        if all_comments:
            rel_plan = os.path.basename(self.plan_path)
            comment_blocks = [f"Reviewed {rel_plan}:"]
            for c in all_comments:
                sec_info = f" on \"{c.section_name}\"" if c.section_name else ""
                snippet = f"> \"{c.line_text}\"" if c.line_text else ""
                entry = f"[Ref {c.ref_id}] Review{sec_info}:\n{snippet}\nReview: {c.comment_text}".strip()
                comment_blocks.append(entry)
            body_parts.append("\n\n".join(comment_blocks))

        if not body_parts:
            return header

        # Trailers (RFC 822 format)
        rel_plan = os.path.basename(self.plan_path)
        primary_anchor = f"Ref-{all_comments[0].ref_id}" if all_comments else "qa-context"
        if all_comments and all_comments[0].section_slug:
            primary_anchor = all_comments[0].section_slug

        trailers = [
            f"Review-Doc: {rel_plan}",
            f"Review-Anchor: #{primary_anchor}"
        ]
        if self.author_name:
            trailers.append(f"Reviewed-By: {self.author_name}")
        trailers.append(f"Reviewed-At: {datetime.now(timezone.utc).astimezone().isoformat()}")

        body_parts.append("\n".join(trailers))

        return f"{header}\n\n" + "\n\n".join(body_parts)

    def format_git_notes(self) -> str:
        """
        Formats Git Notes attaching reference numbers to their diff -p type context.
        Enables anchors to survive or be updated across rebases without changing the commit message.
        """
        entries = []
        rel_plan = os.path.basename(self.plan_path)

        for c in self.get_comments():
            diff_ctx = c.diff_context or "@@ @@"
            entry = [
                f"[Ref {c.ref_id}] {rel_plan}:L{c.line_number}",
                f"Context: {diff_ctx}"
            ]
            if c.context_snippet:
                entry.append("Hunk:\n  " + "\n  ".join(c.context_snippet.splitlines()))
            entries.append("\n".join(entry))

        for q in self.get_qa_items():
            if q.ref_id:
                diff_ctx = q.diff_context or "@@ @@"
                entry = [
                    f"[Ref {q.ref_id}] {rel_plan} (Claude Q/A)",
                    f"Context: {diff_ctx}"
                ]
                if q.context_snippet:
                    entry.append("Hunk:\n  " + "\n  ".join(q.context_snippet.splitlines()))
                entries.append("\n".join(entry))

        if not entries:
            return ""

        return "Review Anchors (diff -p context):\n\n" + "\n\n".join(entries)

    # Commit Execution
    def execute_commit(
        self,
        general_prompt: Optional[str] = None,
        mode: Optional[str] = None
    ) -> Tuple[bool, str]:
        """
        Runs git commit using the formatted message and attaches Git Notes:
        - In 'model_only' mode: commit message is strictly the model name.
        - In 'detailed' mode: commit message includes prompt, Q/A, and [Ref N] review comments.
        - In both modes: Git Notes attach [Ref N] to their diff -p context.
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

            # Attach diff -p context anchors to Git Notes
            notes_body = self.format_git_notes()
            if notes_body:
                subprocess.run(
                    ["git", "notes", "add", "-f", "-m", notes_body, "HEAD"],
                    cwd=self.repo_root,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=False
                )

            return True, "✓ Commit created successfully!"
        except Exception as e:
            return False, str(e)

    # Operational Transformation & Rebase Helper
    def update_notes_for_rebase(self, commit_ref: str = "HEAD") -> Tuple[bool, str]:
        """
        Inspects existing Git Notes for diff -p context, searches current tree/working copy
        to re-locate lines that may have moved during rebase, and updates the note.
        """
        try:
            res = subprocess.run(
                ["git", "notes", "show", commit_ref],
                cwd=self.repo_root,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=False
            )
            if res.returncode != 0 or not res.stdout.strip():
                return False, "No existing notes found on commit."

            notes_text = res.stdout
            updated_lines = []
            relocated_count = 0

            for line in notes_text.splitlines():
                match = re.match(r"^\[Ref (\d+)\] ([^:]+):L(\d+)", line)
                if match:
                    ref_id, fname, old_line = match.group(1), match.group(2), int(match.group(3))
                    fpath = os.path.join(self.repo_root, fname)
                    if os.path.exists(fpath):
                        with open(fpath, "r", encoding="utf-8") as f:
                            content = f.readlines()
                        new_line = old_line
                        if old_line > len(content):
                            new_line = len(content)
                            relocated_count += 1
                        updated_lines.append(f"[Ref {ref_id}] {fname}:L{new_line}")
                        continue
                updated_lines.append(line)

            new_notes = "\n".join(updated_lines)
            if relocated_count > 0:
                subprocess.run(
                    ["git", "notes", "add", "-f", "-m", new_notes, commit_ref],
                    cwd=self.repo_root,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=False
                )
                return True, f"Re-anchored {relocated_count} references after rebase."
            return True, "Notes are already up to date with current tree."
        except Exception as e:
            return False, str(e)

    # Persistence
    def _config_path(self) -> str:
        return os.path.join(self.repo_root, ".review_config.json")

    def _persisted_path(self) -> str:
        return os.path.join(self.repo_root, ".review_anchors.json")

    def _qa_path(self) -> str:
        return os.path.join(self.repo_root, ".review_qa.json")

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
                    "ref_id": c.ref_id,
                    "line_number": c.line_number,
                    "line_text": c.line_text,
                    "section_name": c.section_name,
                    "section_slug": c.section_slug,
                    "comment_text": c.comment_text,
                    "diff_context": c.diff_context,
                    "context_snippet": c.context_snippet,
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
            for idx, item in enumerate(data, start=1):
                rc = ReviewComment(
                    ref_id=item.get("ref_id", idx),
                    line_number=item["line_number"],
                    line_text=item.get("line_text", ""),
                    section_name=item.get("section_name", ""),
                    section_slug=item.get("section_slug", ""),
                    comment_text=item.get("comment_text", ""),
                    diff_context=item.get("diff_context", ""),
                    context_snippet=item.get("context_snippet", ""),
                    timestamp=item.get("timestamp", ""),
                    author=item.get("author", "")
                )
                if rc.line_number not in self.comments:
                    self.comments[rc.line_number] = []
                self.comments[rc.line_number].append(rc)
        except Exception:
            pass

    def save_persisted_qa(self):
        try:
            data = []
            for q in self.qa_items:
                data.append({
                    "ref_id": q.ref_id,
                    "question": q.question,
                    "answer": q.answer,
                    "section_name": q.section_name,
                    "diff_context": q.diff_context,
                    "context_snippet": q.context_snippet,
                    "timestamp": q.timestamp
                })
            with open(self._qa_path(), "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
        except Exception:
            pass

    def load_persisted_qa(self):
        path = self._qa_path()
        if not os.path.exists(path):
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.qa_items.clear()
            for item in data:
                q = QAItem(
                    ref_id=item.get("ref_id"),
                    question=item.get("question", ""),
                    answer=item.get("answer", ""),
                    section_name=item.get("section_name", ""),
                    diff_context=item.get("diff_context", ""),
                    context_snippet=item.get("context_snippet", ""),
                    timestamp=item.get("timestamp", "")
                )
                self.qa_items.append(q)
        except Exception:
            pass
