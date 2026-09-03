"""
The exchange log format.

An *exchange* is one Q/A turn with a model: the prompt that was sent, the
review comments anchored to lines of a design doc that went with it, and the
response that came back.  It is stored as one markdown file per turn under
``reviews/`` and it is the single source of truth; the git commit message for
the turn is *derived* from it.

Design constraints (see review-anchor/README.md for the rationale):

* The commit message keeps its existing shape -- subject line is a short label
  (by convention the model name), body is the prompt verbatim.  Every commit
  already in this repo parses as a valid exchange with an empty response.
* Everything added on top is optional and git-native: ``@@ file:line @@``
  anchor blocks (unified-diff flavoured) and RFC 822 trailers.
* Both directions are plain text a human can type in vim without the tool.

File layout::

    ---
    model: claude opus 5
    doc: implementation_plan.md
    doc-rev: 7353a60
    date: 2026-09-03T11:25:08-07:00
    state: open
    ---

    ## @prompt

    Free prose.  Verbatim what gets pasted into the model.

    ## @anchors

    @@ implementation_plan.md:16 §user-review-required @@
    > **Git Commit Message Format Compatibility**:
    The quoted line above is context for relocating this anchor;
    these lines are the comment.

    ## @response

    Verbatim model prose, pasted back.

    ## @notes

    Private scratch.  Never sent, never committed to the message.

Section headers are ``## @<name>`` at column zero, outside fenced code.  Any
other heading -- including headings inside the pasted prompt or response -- is
ordinary content, so transcripts survive round-tripping unmangled.
"""

from dataclasses import dataclass, field
from datetime import datetime, timezone
import hashlib
import os
import re
from typing import Dict, List, Optional, Sequence, Tuple

SECTIONS = ("prompt", "anchors", "response", "notes")

SECTION_RE = re.compile(r"^##[ \t]+@(" + "|".join(SECTIONS) + r")[ \t]*$")
FENCE_RE = re.compile(r"^[ \t]{0,3}(```+|~~~+)")
ANCHOR_RE = re.compile(
    r"^@@[ \t]+(?P<path>[^\s:]+):(?P<line>\d+)(?:,(?P<count>\d+))?"
    r"(?:[ \t]+§(?P<slug>\S*))?[ \t]+@@[ \t]*$"
)
TRAILER_RE = re.compile(r"^([A-Za-z][A-Za-z0-9-]*):[ \t](.*)$")

#: A final paragraph is only treated as trailers if it carries one of these.
KNOWN_TRAILERS = {
    "review-doc",
    "review-log",
    "reviewed-by",
    "co-authored-by",
    "claude-session",
    "signed-off-by",
}

META_ORDER = ("model", "subject", "doc", "doc-rev", "date", "state")


def now_stamp() -> str:
    return datetime.now(timezone.utc).astimezone().replace(microsecond=0).isoformat()


def blob_rev(path: str, short: int = 7) -> str:
    """git's blob object id for a file, computed without shelling out.

    Works on files that were never committed, which is the common case while a
    plan is still being edited.  Used to pin anchors to a doc revision.
    """
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError:
        return ""
    h = hashlib.sha1()
    h.update(b"blob %d\0" % len(data))
    h.update(data)
    return h.hexdigest()[:short] if short else h.hexdigest()


def _strip_blanks(lines: List[str]) -> List[str]:
    start, end = 0, len(lines)
    while start < end and not lines[start].strip():
        start += 1
    while end > start and not lines[end - 1].strip():
        end -= 1
    return lines[start:end]


def _block(text: str) -> str:
    return "\n".join(_strip_blanks(text.splitlines()))


@dataclass
class Anchor:
    """A review comment pinned to a line of a document."""

    path: str
    line: int
    comment: str = ""
    quote: List[str] = field(default_factory=list)
    slug: str = ""
    count: int = 1

    @property
    def span(self) -> Tuple[int, int]:
        return self.line, self.line + max(1, self.count) - 1

    def header(self) -> str:
        loc = f"{self.path}:{self.line}"
        if self.count and self.count > 1:
            loc += f",{self.count}"
        sec = f" §{self.slug}" if self.slug else ""
        return f"@@ {loc}{sec} @@"

    def render(self) -> str:
        out = [self.header()]
        out += [f"> {q}".rstrip() for q in self.quote]
        body = _block(self.comment)
        if body:
            out.append(body)
        return "\n".join(out)

    # -- verification -------------------------------------------------
    def matches(self, doc_lines: Sequence[str]) -> bool:
        if not self.quote:
            return 1 <= self.line <= len(doc_lines)
        got = doc_lines[self.line - 1 : self.line - 1 + len(self.quote)]
        if len(got) != len(self.quote):
            return False
        return all(a.strip() == b.strip() for a, b in zip(got, self.quote))

    def relocate(self, doc_lines: Sequence[str]) -> Optional[int]:
        """Find where the quoted context moved to, 1-indexed, or None."""
        if not self.quote:
            return None
        want = [q.strip() for q in self.quote]
        n = len(want)
        hits = [
            i + 1
            for i in range(0, max(0, len(doc_lines) - n + 1))
            if [l.strip() for l in doc_lines[i : i + n]] == want
        ]
        if not hits:
            return None
        return min(hits, key=lambda h: abs(h - self.line))


def parse_anchors(text: str) -> List[Anchor]:
    anchors: List[Anchor] = []
    cur: Optional[Anchor] = None
    body: List[str] = []
    in_quote = False

    def flush():
        if cur is not None:
            cur.comment = _block("\n".join(body))
            anchors.append(cur)

    for raw in text.splitlines():
        m = ANCHOR_RE.match(raw)
        if m:
            flush()
            body = []
            in_quote = True
            cur = Anchor(
                path=m.group("path"),
                line=int(m.group("line")),
                count=int(m.group("count") or 1),
                slug=m.group("slug") or "",
            )
            continue
        if cur is None:
            continue
        # Quote lines are the contiguous '>' run right after the header; once
        # ordinary text starts, everything left belongs to the comment.
        if in_quote and (raw.startswith(">") or not raw.strip()):
            if raw.startswith(">"):
                cur.quote.append(raw[1:].lstrip(" "))
                continue
            if not cur.quote:
                continue
            in_quote = False
            continue
        in_quote = False
        body.append(raw)
    flush()
    return anchors


def render_anchors(anchors: Sequence[Anchor]) -> str:
    return "\n\n".join(a.render() for a in anchors)


def split_trailers(body: str) -> Tuple[str, List[Tuple[str, str]]]:
    """Peel an RFC 822 trailer block off the end of a commit body."""
    lines = body.rstrip().splitlines()
    idx = len(lines)
    while idx > 0 and lines[idx - 1].strip():
        idx -= 1
    tail = lines[idx:]
    if not tail:
        return body, []
    pairs: List[Tuple[str, str]] = []
    for line in tail:
        m = TRAILER_RE.match(line)
        if not m:
            return body, []
        pairs.append((m.group(1), m.group(2).strip()))
    if not any(k.lower() in KNOWN_TRAILERS for k, _ in pairs):
        return body, []
    return "\n".join(lines[:idx]).rstrip(), pairs


@dataclass
class Exchange:
    """One Q/A turn."""

    meta: Dict[str, str] = field(default_factory=dict)
    prompt: str = ""
    anchors: List[Anchor] = field(default_factory=list)
    response: str = ""
    notes: str = ""
    path: Optional[str] = None

    # -- convenience accessors ---------------------------------------
    @property
    def model(self) -> str:
        return self.meta.get("model", "")

    @property
    def subject(self) -> str:
        return self.meta.get("subject") or self.meta.get("model", "")

    @property
    def doc(self) -> str:
        return self.meta.get("doc", "")

    @property
    def state(self) -> str:
        return self.meta.get("state", "open")

    def set(self, key: str, value: str) -> None:
        self.meta[key] = value

    def anchors_for(self, path: str) -> List[Anchor]:
        base = os.path.basename(path)
        return [a for a in self.anchors if a.path == path or a.path == base]

    def sort_anchors(self) -> None:
        self.anchors.sort(key=lambda a: (a.path, a.line))

    # -- serialisation ------------------------------------------------
    @classmethod
    def parse(cls, text: str, path: Optional[str] = None) -> "Exchange":
        meta: Dict[str, str] = {}
        lines = text.splitlines()
        i = 0
        if lines and lines[0].strip() == "---":
            i = 1
            while i < len(lines) and lines[i].strip() != "---":
                m = TRAILER_RE.match(lines[i])
                if m:
                    meta[m.group(1).strip().lower()] = m.group(2).strip()
                i += 1
            i += 1

        buckets: Dict[str, List[str]] = {s: [] for s in SECTIONS}
        current: Optional[str] = None
        fence: Optional[str] = None
        for raw in lines[i:]:
            fm = FENCE_RE.match(raw)
            if fm:
                tok = fm.group(1)[:3]
                fence = None if fence == tok else (fence or tok)
            if fence is None:
                sm = SECTION_RE.match(raw)
                if sm:
                    current = sm.group(1)
                    continue
            if current:
                buckets[current].append(raw)

        return cls(
            meta=meta,
            prompt=_block("\n".join(buckets["prompt"])),
            anchors=parse_anchors("\n".join(buckets["anchors"])),
            response=_block("\n".join(buckets["response"])),
            notes=_block("\n".join(buckets["notes"])),
            path=path,
        )

    @classmethod
    def load(cls, path: str) -> "Exchange":
        with open(path, "r", encoding="utf-8") as fh:
            return cls.parse(fh.read(), path=path)

    def dumps(self) -> str:
        keys = [k for k in META_ORDER if self.meta.get(k)]
        keys += [k for k in self.meta if k not in META_ORDER and self.meta[k]]
        out = ["---"]
        out += [f"{k}: {self.meta[k]}" for k in keys]
        out += ["---", ""]
        out += ["## @prompt", "", self.prompt, ""]
        out += ["## @anchors", "", render_anchors(self.anchors), ""]
        out += ["## @response", "", self.response, ""]
        out += ["## @notes", "", self.notes, ""]
        text = "\n".join(out)
        return re.sub(r"\n{3,}", "\n\n", text).rstrip() + "\n"

    def save(self, path: Optional[str] = None) -> str:
        target = path or self.path
        if not target:
            raise ValueError("exchange has no path")
        os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
        with open(target, "w", encoding="utf-8") as fh:
            fh.write(self.dumps())
        self.path = target
        return target

    # -- derived artefacts --------------------------------------------
    def compose_prompt(self) -> str:
        """What gets copied to the clipboard and pasted into the model."""
        parts = [p for p in (self.prompt.strip(),) if p]
        if self.anchors:
            head = f"Review comments on {self.doc}:" if self.doc else "Review comments:"
            parts.append(head + "\n\n" + render_anchors(self.anchors))
        return "\n\n".join(parts)

    def trailers(self, log_path: str = "", extra: Sequence[Tuple[str, str]] = ()) -> List[Tuple[str, str]]:
        out: List[Tuple[str, str]] = []
        if self.doc:
            rev = self.meta.get("doc-rev", "")
            out.append(("Review-Doc", f"{self.doc}@{rev}" if rev else self.doc))
        rel = log_path or (self.path or "")
        if rel:
            out.append(("Review-Log", rel))
        out.extend(extra)
        return out

    def commit_message(
        self,
        log_path: str = "",
        extra_trailers: Sequence[Tuple[str, str]] = (),
        bare: bool = False,
    ) -> str:
        """Render the commit message for this turn.

        ``bare`` reproduces the temporary-commit style bookmarked at the
        ``pending-push`` tag: subject line only.
        """
        subject = (self.subject or "").strip() or "(no subject)"
        if bare:
            return subject
        blocks: List[str] = []
        if self.prompt.strip():
            blocks.append(self.prompt.strip())
        if self.anchors:
            blocks.append(render_anchors(self.anchors))
        trailers = self.trailers(log_path=log_path, extra=extra_trailers)
        if trailers:
            blocks.append("\n".join(f"{k}: {v}" for k, v in trailers))
        if not blocks:
            return subject
        return subject + "\n\n" + "\n\n".join(blocks) + "\n"

    @classmethod
    def from_commit_message(cls, message: str, **meta: str) -> "Exchange":
        """Inverse of :meth:`commit_message`; also the history importer.

        Commits written before this format existed have no anchors and no
        trailers, and come back as an exchange whose prompt is the whole body.
        """
        raw = message.replace("\r\n", "\n")
        head, _, body = raw.partition("\n")
        body, pairs = split_trailers(body.strip("\n"))
        found = {k.lower(): v for k, v in pairs}

        idx = None
        for n, line in enumerate(body.splitlines()):
            if ANCHOR_RE.match(line):
                idx = n
                break
        lines = body.splitlines()
        prompt = "\n".join(lines[:idx] if idx is not None else lines)
        anchors = parse_anchors("\n".join(lines[idx:])) if idx is not None else []

        ex = cls(prompt=_block(prompt), anchors=anchors)
        ex.meta["model"] = head.strip()
        doc = found.get("review-doc", "")
        if doc:
            name, _, rev = doc.partition("@")
            ex.meta["doc"] = name
            if rev:
                ex.meta["doc-rev"] = rev
        for k, v in meta.items():
            if v:
                ex.meta[k.replace("_", "-")] = v
        return ex
