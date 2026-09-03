"""
Tests for the exchange format.

The load-bearing property is backwards compatibility: every commit message
already in this repo's history has to read back as a valid exchange, and an
exchange has to render to a message of the same shape.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

PKG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PKG not in sys.path:
    sys.path.insert(0, PKG)

from tui.exchange import Anchor, Exchange, blob_rev, parse_anchors, split_trailers  # noqa: E402
from tui.git_anchoring import Git, import_history  # noqa: E402
from tui.markdown_parser import MarkdownParser  # noqa: E402
from tui.store import ReviewStore, slugify  # noqa: E402

PLAN = """# Plan Title

## User Review Required

> [!IMPORTANT]
> The corner lines must be 60mm long.

```swift
let anchor = RealityAnchor()
```

- Item 1
- Item 2
"""

# Verbatim from this repo's history (commit c79cec2), the shape every new
# commit message must stay compatible with.
LEGACY_MESSAGE = """gemini 3.8 flash high

the paid app is already made, called "Silly Bells" on iOS, and, long term, I want the scanner as a PWA, but start by re-generating the implementation plan with just the name change and suggest a way to anchor git commit message lines in order to document the review.
"""

BARE_MESSAGE = "gemini 3.8 flash high"


class TestMarkdownParser(unittest.TestCase):
    def test_parse_sample(self):
        lines = MarkdownParser.parse_text(PLAN)
        self.assertEqual(len(lines), 13)
        self.assertEqual(lines[0].heading_slug, "plan-title")
        self.assertEqual(lines[2].heading_slug, "user-review-required")
        self.assertEqual(lines[4].alert_type, "IMPORTANT")
        self.assertEqual(lines[7].line_type, "code_fence")
        self.assertEqual(lines[8].line_type, "code_body")

    def test_heading_slug_is_the_full_github_anchor(self):
        self.assertEqual(
            MarkdownParser.slugify("Component 1: TargetCore (Shared Multi-Platform Swift Package)"),
            "component-1-targetcore-shared-multi-platform-swift-package",
        )

    def test_filename_slug_truncates_on_a_word_boundary(self):
        self.assertEqual(
            slugify("Component 1: TargetCore (Shared Multi-Platform Swift Package)"),
            "component-1-targetcore-shared-multi-platform",
        )


class TestBackwardsCompatibility(unittest.TestCase):
    def test_legacy_message_parses(self):
        ex = Exchange.from_commit_message(LEGACY_MESSAGE)
        self.assertEqual(ex.model, "gemini 3.8 flash high")
        self.assertTrue(ex.prompt.startswith("the paid app is already made"))
        self.assertEqual(ex.anchors, [])
        self.assertEqual(ex.response, "")

    def test_legacy_message_round_trips_byte_for_byte(self):
        ex = Exchange.from_commit_message(LEGACY_MESSAGE)
        self.assertEqual(ex.commit_message().rstrip("\n"), LEGACY_MESSAGE.rstrip("\n"))

    def test_bare_message(self):
        ex = Exchange.from_commit_message(BARE_MESSAGE)
        self.assertEqual(ex.model, "gemini 3.8 flash high")
        self.assertEqual(ex.prompt, "")
        self.assertEqual(ex.commit_message(bare=True), BARE_MESSAGE)

    def test_subject_overrides_model(self):
        ex = Exchange(meta={"model": "claude opus 5", "subject": "manual change"})
        self.assertEqual(ex.commit_message(), "manual change")

    def test_prompt_ending_in_a_colon_line_is_not_eaten_as_trailers(self):
        body, pairs = split_trailers("do the thing\n\nNote: this is prose, not a trailer")
        self.assertEqual(pairs, [])
        self.assertTrue(body.endswith("not a trailer"))


class TestAnchors(unittest.TestCase):
    def setUp(self):
        self.doc = PLAN.splitlines()

    def anchor(self, line=5, count=2):
        return Anchor(
            path="implementation_plan.md",
            line=line,
            count=count,
            slug="user-review-required",
            quote=self.doc[line - 1 : line - 1 + count],
            comment="60mm has to match the printer's margins.",
        )

    def test_header_shape(self):
        self.assertEqual(
            self.anchor().header(), "@@ implementation_plan.md:5,2 §user-review-required @@"
        )

    def test_render_parse_round_trip(self):
        original = self.anchor()
        again = parse_anchors(original.render())[0]
        self.assertEqual(again.path, original.path)
        self.assertEqual(again.line, original.line)
        self.assertEqual(again.count, original.count)
        self.assertEqual(again.slug, original.slug)
        self.assertEqual(again.quote, original.quote)
        self.assertEqual(again.comment, original.comment)

    def test_multiline_comment_survives(self):
        a = self.anchor()
        a.comment = "first line\n\nsecond paragraph"
        self.assertEqual(parse_anchors(a.render())[0].comment, a.comment)

    def test_matches_and_relocates(self):
        a = self.anchor()
        self.assertTrue(a.matches(self.doc))
        moved = ["# New preamble", ""] + self.doc
        self.assertFalse(a.matches(moved))
        self.assertEqual(a.relocate(moved), a.line + 2)

    def test_relocate_returns_none_when_text_is_gone(self):
        a = self.anchor()
        self.assertIsNone(a.relocate(["nothing", "like", "the", "quote"]))


class TestExchangeFile(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.plan = os.path.join(self.tmp.name, "implementation_plan.md")
        with open(self.plan, "w", encoding="utf-8") as fh:
            fh.write(PLAN)

    def tearDown(self):
        self.tmp.cleanup()

    def make(self):
        ex = Exchange(
            meta={"model": "claude opus 5", "doc": "implementation_plan.md", "doc-rev": "abc1234"},
            prompt="Rework the anchoring format.\n\nSecond paragraph.",
            response="## A heading inside the response\n\nand ```fenced``` text",
            notes="private",
            anchors=[
                Anchor(
                    path="implementation_plan.md",
                    line=3,
                    quote=["## User Review Required"],
                    comment="Keep this section.",
                    slug="user-review-required",
                )
            ],
        )
        return ex

    def test_file_round_trip(self):
        ex = self.make()
        again = Exchange.parse(ex.dumps())
        self.assertEqual(again.prompt, ex.prompt)
        self.assertEqual(again.response, ex.response)
        self.assertEqual(again.notes, ex.notes)
        self.assertEqual(len(again.anchors), 1)
        self.assertEqual(again.meta["model"], "claude opus 5")

    def test_headings_in_pasted_text_are_not_section_markers(self):
        ex = self.make()
        ex.response = "## @prompt is only special at column zero\n\n    ## @notes indented"
        again = Exchange.parse(ex.dumps())
        self.assertIn("## @notes indented", again.response)
        self.assertEqual(again.prompt, ex.prompt)

    def test_commit_message_shape(self):
        ex = self.make()
        message = ex.commit_message(log_path="reviews/0001-x.md")
        lines = message.splitlines()
        self.assertEqual(lines[0], "claude opus 5")
        self.assertEqual(lines[1], "")
        self.assertIn("Rework the anchoring format.", message)
        self.assertIn("@@ implementation_plan.md:3 §user-review-required @@", message)
        self.assertIn("Review-Doc: implementation_plan.md@abc1234", message)
        self.assertIn("Review-Log: reviews/0001-x.md", message)
        self.assertNotIn("A heading inside the response", message)

    def test_commit_message_round_trip(self):
        ex = self.make()
        again = Exchange.from_commit_message(ex.commit_message(log_path="reviews/0001-x.md"))
        self.assertEqual(again.prompt, ex.prompt)
        self.assertEqual(again.anchors[0].line, 3)
        self.assertEqual(again.anchors[0].comment, "Keep this section.")
        self.assertEqual(again.meta["doc"], "implementation_plan.md")
        self.assertEqual(again.meta["doc-rev"], "abc1234")

    def test_composed_prompt_carries_anchors(self):
        composed = self.make().compose_prompt()
        self.assertIn("Rework the anchoring format.", composed)
        self.assertIn("@@ implementation_plan.md:3", composed)

    def test_blob_rev_matches_git(self):
        if not shutil.which("git"):
            self.skipTest("git not available")
        out = subprocess.run(
            ["git", "hash-object", self.plan], capture_output=True, text=True, check=False
        ).stdout.strip()
        self.assertTrue(out.startswith(blob_rev(self.plan)))


class TestStoreAndImport(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        with open(os.path.join(self.root, "implementation_plan.md"), "w", encoding="utf-8") as fh:
            fh.write(PLAN)
        self.store = ReviewStore(self.root)

    def tearDown(self):
        self.tmp.cleanup()

    def test_numbering_and_current(self):
        first = self.store.create("claude opus 5", doc="implementation_plan.md", title="first turn")
        self.assertTrue(first.path.endswith("0001-first-turn.md"))
        self.assertEqual(self.store.next_number(), 2)
        first.meta["state"] = "closed"
        first.save()
        second = self.store.create("claude opus 5", title="second turn")
        self.assertEqual(self.store.number_of(self.store.current()), self.store.number_of(second))

    def _git(self, *args):
        subprocess.run(["git", *args], cwd=self.root, capture_output=True, check=False)

    def test_import_history(self):
        if not shutil.which("git"):
            self.skipTest("git not available")
        self._git("init", "-q")
        self._git("config", "user.email", "test@example.com")
        self._git("config", "user.name", "Test")
        self._git("add", "-A")
        self._git("commit", "-m", LEGACY_MESSAGE)
        self._git("commit", "--allow-empty", "-m", BARE_MESSAGE)

        written = import_history(Git(self.root), self.store)
        self.assertEqual(len(written), 2)
        first = Exchange.load(written[0])
        self.assertEqual(first.model, "gemini 3.8 flash high")
        self.assertTrue(first.prompt.startswith("the paid app"))
        self.assertEqual(first.state, "closed")
        self.assertTrue(first.meta.get("commit"))
        self.assertEqual(Exchange.load(written[1]).prompt, "")


if __name__ == "__main__":
    unittest.main()
