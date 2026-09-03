"""
The ``reviews/`` directory: one markdown file per exchange, numbered in turn
order, tracked in git alongside the code the turn produced.

    reviews/0001-avp-spatial-targets.md
    reviews/0002-silly-bells-rename.md
    ...

An exchange is *open* while it is being drafted and *closed* once it has been
committed.  The tool never needs to write the file after the commit exists --
the link back runs through the ``Review-Log:`` trailer -- so the file that
lands in the commit is already final.
"""

import os
import re
from typing import List, Optional, Tuple

from .exchange import Exchange, blob_rev, now_stamp

NAME_RE = re.compile(r"^(\d{4})-(.*)\.md$")


def slugify(text: str, limit: int = 48) -> str:
    """Filename-safe slug, truncated on a word boundary."""
    slug = re.sub(r"[^\w\s-]", "", (text or "").lower())
    slug = re.sub(r"[-\s]+", "-", slug).strip("-")
    if len(slug) > limit:
        cut = slug[: limit + 1]
        slug = cut[: cut.rindex("-")] if "-" in cut[:-1] else cut[:limit]
    return slug.strip("-") or "exchange"


class ReviewStore:
    DIRNAME = "reviews"

    def __init__(self, repo_root: str, dirname: Optional[str] = None):
        self.repo_root = repo_root
        self.dirname = dirname or self.DIRNAME
        self.dir = os.path.join(repo_root, self.dirname)

    # -- listing --------------------------------------------------------
    def entries(self) -> List[Tuple[int, str]]:
        if not os.path.isdir(self.dir):
            return []
        found = []
        for name in os.listdir(self.dir):
            m = NAME_RE.match(name)
            if m:
                found.append((int(m.group(1)), os.path.join(self.dir, name)))
        return sorted(found)

    def paths(self) -> List[str]:
        return [p for _, p in self.entries()]

    def next_number(self) -> int:
        entries = self.entries()
        return (entries[-1][0] + 1) if entries else 1

    def rel(self, path: str) -> str:
        return os.path.relpath(path, self.repo_root)

    # -- load / create ---------------------------------------------------
    def load(self, number: int) -> Optional[Exchange]:
        for num, path in self.entries():
            if num == number:
                return Exchange.load(path)
        return None

    def load_path(self, path: str) -> Exchange:
        return Exchange.load(path)

    def latest(self) -> Optional[Exchange]:
        entries = self.entries()
        return Exchange.load(entries[-1][1]) if entries else None

    def current(self) -> Optional[Exchange]:
        """Newest open exchange, i.e. the one being drafted."""
        for _, path in reversed(self.entries()):
            ex = Exchange.load(path)
            if ex.state != "closed":
                return ex
        return None

    def number_of(self, ex: Exchange) -> Optional[int]:
        if not ex.path:
            return None
        m = NAME_RE.match(os.path.basename(ex.path))
        return int(m.group(1)) if m else None

    def create(
        self,
        model: str,
        doc: str = "",
        title: str = "",
        prompt: str = "",
    ) -> Exchange:
        number = self.next_number()
        slug = slugify(title or prompt.splitlines()[0] if prompt else title or model)
        path = os.path.join(self.dir, f"{number:04d}-{slug}.md")
        ex = Exchange(prompt=prompt, path=path)
        ex.meta["model"] = model
        if doc:
            ex.meta["doc"] = os.path.relpath(doc, self.repo_root) if os.path.isabs(doc) else doc
            ex.meta["doc-rev"] = blob_rev(doc if os.path.isabs(doc) else os.path.join(self.repo_root, doc))
        ex.meta["date"] = now_stamp()
        ex.meta["state"] = "open"
        ex.save()
        return ex
