"""
Git plumbing for Review Anchor.

Everything about *message shape* lives in :mod:`tui.exchange`; this module only
talks to git -- branch and tag inspection, committing, and reading history back
out so old commits can be imported into the exchange log.

The commit convention this preserves, as practised in this repo's history:

* subject line is a short label, by convention the model name
  (``gemini 3.8 flash high``), sometimes a plain note (``manual change``);
* the body, when there is one, is the prompt verbatim;
* the ``pending-push`` tag bookmarks the subject-only "temporary commit" style.

Nothing here contacts a model API.  Prompts and responses move by clipboard.
"""

from dataclasses import dataclass
import json
import os
import subprocess
from typing import Dict, List, Optional, Sequence, Tuple

from .exchange import Exchange
from .store import slugify

RECORD_SEP = "\x1e"
FIELD_SEP = "\x1f"


@dataclass
class CommitRecord:
    sha: str
    short: str
    date: str
    author: str
    message: str


class Git:
    """Thin wrapper over the handful of git commands the tool needs."""

    def __init__(self, repo_root: Optional[str] = None):
        self.repo_root = repo_root or self.discover_root()

    @staticmethod
    def discover_root(start: Optional[str] = None) -> str:
        res = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=start or os.getcwd(),
            capture_output=True,
            text=True,
            check=False,
        )
        if res.returncode == 0 and res.stdout.strip():
            return res.stdout.strip()
        return start or os.getcwd()

    def run(self, *args: str) -> Tuple[int, str, str]:
        res = subprocess.run(
            ["git", *args], cwd=self.repo_root, capture_output=True, text=True, check=False
        )
        return res.returncode, res.stdout.strip(), res.stderr.strip()

    def out(self, *args: str, default: str = "") -> str:
        code, out, _ = self.run(*args)
        return out if code == 0 else default

    # -- inspection ------------------------------------------------------
    def current_branch(self) -> str:
        return self.out("rev-parse", "--abbrev-ref", "HEAD", default="unknown")

    def default_branch(self) -> str:
        ref = self.out("symbolic-ref", "refs/remotes/origin/HEAD")
        if ref:
            return ref.replace("refs/remotes/origin/", "")
        return "staging"

    def author(self) -> str:
        name = self.out("config", "user.name")
        email = self.out("config", "user.email")
        if name and email:
            return f"{name} <{email}>"
        # Fall back to whoever authored the last commit: the tool is often run
        # somewhere the global git config is not visible.
        return name or self.out("log", "-1", "--format=%an <%ae>") or "Reviewer"

    def tag_info(self, tag: str = "pending-push") -> Tuple[Optional[str], bool]:
        """(short sha of the tag, whether HEAD is sitting on it)."""
        code, sha, _ = self.run("rev-parse", "--short", tag)
        if code != 0:
            return None, False
        head = self.out("rev-parse", "--short", "HEAD")
        return sha, sha == head

    def is_dirty(self) -> bool:
        return bool(self.out("status", "--porcelain"))

    def blob_rev(self, path: str, short: int = 7) -> str:
        return self.out("hash-object", path)[:short]

    # -- history ---------------------------------------------------------
    def log(self, limit: int = 0, rev_range: str = "HEAD") -> List[CommitRecord]:
        fmt = FIELD_SEP.join(["%H", "%h", "%aI", "%an <%ae>", "%B"]) + RECORD_SEP
        args = ["log", "--reverse", "--no-merges", f"--format={fmt}"]
        if limit:
            args += [f"-n{limit}"]
        args += [rev_range]
        code, out, _ = self.run(*args)
        if code != 0:
            return []
        records = []
        for chunk in out.split(RECORD_SEP):
            if not chunk.strip():
                continue
            parts = chunk.lstrip("\n").split(FIELD_SEP)
            if len(parts) < 5:
                continue
            records.append(
                CommitRecord(
                    sha=parts[0], short=parts[1], date=parts[2], author=parts[3], message=parts[4]
                )
            )
        return records

    def find_commit_for_log(self, rel_log_path: str) -> Optional[str]:
        """Locate the commit whose trailer points at an exchange file."""
        out = self.out("log", "--format=%h", f"--grep=Review-Log: {rel_log_path}")
        return out.splitlines()[0] if out else None

    # -- writing ---------------------------------------------------------
    def commit(self, message: str, add_all: bool = True) -> Tuple[bool, str]:
        if add_all:
            code, _, err = self.run("add", "-A")
            if code != 0:
                return False, f"git add failed: {err}"
        code, out, err = self.run("commit", "-m", message)
        if code != 0:
            return False, (err or out or "git commit failed")
        return True, self.out("log", "-1", "--format=%h %s")


class Config:
    """Small persisted settings blob (``.review_config.json``, gitignored)."""

    FILENAME = ".review_config.json"
    DEFAULTS: Dict[str, object] = {
        "model": "claude opus 5",
        "doc": "implementation_plan.md",
        "bare_commit": False,
        "wrap_width": 80,
        "trailers": [],
    }

    def __init__(self, repo_root: str):
        self.path = os.path.join(repo_root, self.FILENAME)
        self.data = dict(self.DEFAULTS)
        self.load()

    def load(self) -> None:
        try:
            with open(self.path, "r", encoding="utf-8") as fh:
                loaded = json.load(fh)
            if isinstance(loaded, dict):
                self.data.update(loaded)
        except (OSError, ValueError):
            pass

    def save(self) -> None:
        try:
            with open(self.path, "w", encoding="utf-8") as fh:
                json.dump(self.data, fh, indent=2)
        except OSError:
            pass

    def __getitem__(self, key: str):
        return self.data.get(key, self.DEFAULTS.get(key))

    def __setitem__(self, key: str, value) -> None:
        self.data[key] = value
        self.save()

    @property
    def extra_trailers(self) -> List[Tuple[str, str]]:
        out = []
        for item in self.data.get("trailers") or []:
            if isinstance(item, str) and ":" in item:
                k, _, v = item.partition(":")
                out.append((k.strip(), v.strip()))
        return out


def import_history(git: Git, store, limit: int = 0, rev_range: str = "HEAD") -> List[str]:
    """Backfill ``reviews/`` from existing commits.

    Proof that the format is backwards compatible: every commit already in the
    repo -- prompt-in-the-body ones, subject-only temporary commits, the
    GitHub-generated root commit -- reads back as a valid exchange.
    """
    written: List[str] = []
    existing = {os.path.basename(p) for p in store.paths()}
    number = store.next_number()
    for rec in git.log(limit=limit, rev_range=rev_range):
        ex = Exchange.from_commit_message(rec.message, date=rec.date, state="closed")
        ex.meta["commit"] = rec.short
        title = ex.subject if len(ex.subject) < 60 else (ex.prompt.splitlines() or [ex.subject])[0]
        name = f"{number:04d}-{slugify(title)}.md"
        if name in existing:
            continue
        path = os.path.join(store.dir, name)
        ex.save(path)
        written.append(path)
        number += 1
    return written
