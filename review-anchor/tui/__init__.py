"""
Review Anchor.

``exchange``/``store`` are the format library (no curses, no git); ``app`` is
the curses front end; ``git_anchoring`` is the git plumbing.
"""

from .exchange import Anchor, Exchange
from .git_anchoring import Config, Git, import_history
from .markdown_parser import MarkdownLine, MarkdownParser
from .store import ReviewStore

__all__ = [
    "Anchor",
    "Exchange",
    "Config",
    "Git",
    "import_history",
    "MarkdownLine",
    "MarkdownParser",
    "ReviewStore",
]


def __getattr__(name):  # keep curses out of the import path for headless use
    if name in ("ReviewAnchorTUI", "WysiwygRenderer"):
        from . import app, wysiwyg_renderer

        return {"ReviewAnchorTUI": app.ReviewAnchorTUI, "WysiwygRenderer": wysiwyg_renderer.WysiwygRenderer}[name]
    raise AttributeError(name)
