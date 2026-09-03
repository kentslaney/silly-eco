"""
Unit tests for Review Anchor.
Tests markdown parsing, comment anchoring with [Ref N] tags,
rebase-tolerant diff -p Git Notes formatting, Claude Code Q/A integration,
and backwards-compatible git commit formatting.
"""

import os
import sys
import tempfile
import unittest

# Ensure review-anchor directory is in sys.path
pkg_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if pkg_root not in sys.path:
    sys.path.insert(0, pkg_root)

from tui.markdown_parser import MarkdownParser, MarkdownLine
from tui.git_anchoring import GitAnchoring, ReviewComment, QAItem


SAMPLE_MARKDOWN = """# Plan Title

## User Review Required

> [!IMPORTANT]
> The corner lines must be 60mm long.

```swift
let anchor = RealityAnchor()
```

- Item 1
- Item 2
"""


class TestMarkdownParser(unittest.TestCase):
    def test_parse_sample(self):
        lines = MarkdownParser.parse_text(SAMPLE_MARKDOWN)
        self.assertEqual(len(lines), 13)

        # Line 1: H1
        self.assertEqual(lines[0].line_number, 1)
        self.assertEqual(lines[0].line_type, "heading")
        self.assertEqual(lines[0].heading_level, 1)
        self.assertEqual(lines[0].heading_slug, "plan-title")

        # Line 3: H2
        self.assertEqual(lines[2].line_type, "heading")
        self.assertEqual(lines[2].heading_level, 2)
        self.assertEqual(lines[2].heading_slug, "user-review-required")

        # Line 5: Alert
        self.assertEqual(lines[4].line_type, "alert")
        self.assertEqual(lines[4].alert_type, "IMPORTANT")

        # Line 8-10: Code block
        self.assertEqual(lines[7].line_type, "code_fence")
        self.assertEqual(lines[8].line_type, "code_body")
        self.assertEqual(lines[9].line_type, "code_fence")

    def test_slugify(self):
        self.assertEqual(
            MarkdownParser.slugify("Component 1: TargetCore (Shared Multi-Platform Swift Package)"),
            "component-1-targetcore-shared-multi-platform-swift-package"
        )


class TestGitAnchoring(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.plan_path = os.path.join(self.temp_dir.name, "implementation_plan.md")
        with open(self.plan_path, "w", encoding="utf-8") as f:
            f.write(SAMPLE_MARKDOWN)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_model_only_mode(self):
        anchor = GitAnchoring(repo_root=self.temp_dir.name, plan_path=self.plan_path)
        anchor.model_header = "gemini 3.8 flash high"
        anchor.commit_mode = "model_only"

        parsed = MarkdownParser.parse_file(self.plan_path)
        anchor.add_comment(line=parsed[0], comment_text="Test comment")

        # In model_only mode, commit message is strictly the model name
        msg = anchor.format_commit_message(general_prompt="Should be omitted in model_only")
        self.assertEqual(msg, "gemini 3.8 flash high")

        # Review diff -p context is available for Git Notes
        notes = anchor.format_git_notes()
        self.assertIn("[Ref 1] implementation_plan.md:L1", notes)
        self.assertIn("Context: @@ # Plan Title @@", notes)

    def test_detailed_commit_format_with_refs(self):
        anchor = GitAnchoring(repo_root=self.temp_dir.name, plan_path=self.plan_path)
        anchor.model_header = "gemini 3.8 flash high"
        anchor.commit_mode = "detailed"

        parsed = MarkdownParser.parse_file(self.plan_path)
        line5 = parsed[4]

        anchor.add_comment(
            line=line5,
            comment_text="Approved. Ensure 60mm is verified with physical ruler.",
            section_name="User Review Required",
            section_slug="user-review-required"
        )

        commit_msg = anchor.format_commit_message(
            general_prompt="Updated review comments on implementation plan."
        )

        lines = commit_msg.splitlines()

        # Subject line must match model header
        self.assertEqual(lines[0], "gemini 3.8 flash high")
        self.assertEqual(lines[1], "")

        # Body contains general prompt (snapshot of model input)
        self.assertIn("Updated review comments on implementation plan.", commit_msg)

        # Body contains anchored ref identifier instead of raw line number
        self.assertIn("[Ref 1] Review on \"User Review Required\":", commit_msg)
        self.assertIn("Review: Approved. Ensure 60mm is verified with physical ruler.", commit_msg)

        # Body contains RFC 822 trailers
        self.assertIn("Review-Doc: implementation_plan.md", commit_msg)
        self.assertIn("Review-Anchor: #user-review-required", commit_msg)

    def test_diff_p_git_notes_format(self):
        anchor = GitAnchoring(repo_root=self.temp_dir.name, plan_path=self.plan_path)
        parsed = MarkdownParser.parse_file(self.plan_path)
        line5 = parsed[4]  # "> [!IMPORTANT]"

        anchor.add_comment(
            line=line5,
            comment_text="Corner line length check.",
            section_name="User Review Required",
            section_slug="user-review-required"
        )

        notes = anchor.format_git_notes()
        self.assertIn("Review Anchors (diff -p context):", notes)
        self.assertIn("[Ref 1] implementation_plan.md:L5", notes)
        self.assertIn("Context: @@ ## User Review Required @@", notes)
        self.assertIn("The corner lines must be 60mm long.", notes)

    def test_claude_code_qa_integration(self):
        anchor = GitAnchoring(repo_root=self.temp_dir.name, plan_path=self.plan_path)
        anchor.model_header = "claude-3-5-sonnet"
        anchor.commit_mode = "detailed"

        # Add Q/A item anchored to section
        qa = anchor.add_qa(
            question="How should orientation tilt be handled?",
            answer="Reject frames beyond 45° with haptic warning.",
            section_name="User Review Required",
            line_number=5
        )
        self.assertIsNotNone(qa)
        self.assertEqual(qa.ref_id, 1)

        msg = anchor.format_commit_message()
        self.assertIn("claude-3-5-sonnet", msg)
        self.assertIn("Claude Code Q/A Context:", msg)
        self.assertIn("[Ref 1] (User Review Required)", msg)
        self.assertIn("Q: How should orientation tilt be handled?", msg)
        self.assertIn("A: Reject frames beyond 45° with haptic warning.", msg)

        # Git Notes should contain diff -p context for this Ref
        notes = anchor.format_git_notes()
        self.assertIn("[Ref 1] implementation_plan.md (Claude Q/A)", notes)
        self.assertIn("Context: @@ ## User Review Required @@", notes)

    def test_config_persistence(self):
        anchor = GitAnchoring(repo_root=self.temp_dir.name, plan_path=self.plan_path)
        anchor.model_header = "custom-model-2.0"
        anchor.commit_mode = "model_only"
        anchor.save_config()

        anchor2 = GitAnchoring(repo_root=self.temp_dir.name, plan_path=self.plan_path)
        self.assertEqual(anchor2.model_header, "custom-model-2.0")
        self.assertEqual(anchor2.commit_mode, "model_only")

    def test_persistence(self):
        anchor1 = GitAnchoring(repo_root=self.temp_dir.name, plan_path=self.plan_path)
        parsed = MarkdownParser.parse_file(self.plan_path)

        anchor1.add_comment(line=parsed[0], comment_text="Test comment 1")
        anchor1.add_qa(question="Q1", answer="A1")
        self.assertEqual(len(anchor1.get_comments()), 1)
        self.assertEqual(len(anchor1.get_qa_items()), 1)

        anchor2 = GitAnchoring(repo_root=self.temp_dir.name, plan_path=self.plan_path)
        self.assertEqual(len(anchor2.get_comments()), 1)
        self.assertEqual(anchor2.get_comments()[0].comment_text, "Test comment 1")
        self.assertEqual(len(anchor2.get_qa_items()), 1)
        self.assertEqual(anchor2.get_qa_items()[0].question, "Q1")


class MockCursesWindow:
    def __init__(self, max_y=24, max_x=80):
        self.max_y = max_y
        self.max_x = max_x
        self.written = []

    def getmaxyx(self):
        return (self.max_y, self.max_x)

    def addstr(self, y, x, text, attr=0):
        if y == self.max_y - 1 and (x + len(text) >= self.max_x):
            import _curses
            raise _curses.error("addwstr() returned ERR")
        self.written.append((y, x, text, attr))


class TestSafeCurses(unittest.TestCase):
    def test_safe_addstr_prevents_bottom_right_crash(self):
        from tui.app import ReviewAnchorTUI
        tui = ReviewAnchorTUI(plan_path="implementation_plan.md")
        win = MockCursesWindow(max_y=24, max_x=80)

        # Attempting to write full row width on the bottom-most line
        full_line = " " * 80
        tui._safe_addstr(win, 23, 0, full_line)
        self.assertTrue(len(win.written) > 0)
        y, x, text, _ = win.written[0]
        self.assertEqual(y, 23)
        self.assertEqual(x, 0)
        self.assertLess(x + len(text), 80)


class TestCursorVisibilityAndScrolling(unittest.TestCase):
    def test_scrolling_follows_cursor(self):
        from tui.app import ReviewAnchorTUI
        from tui.markdown_parser import MarkdownLine
        tui = ReviewAnchorTUI(plan_path="implementation_plan.md")

        tui.markdown_lines = [
            MarkdownLine(line_number=i, raw_text=f"Line content {i}", line_type="text")
            for i in range(1, 101)
        ]
        tui.selected_line_idx = 0
        tui.scroll_offset = 0

        # Move cursor to line 20 in a 10-row pane
        tui.selected_line_idx = 20
        tui._ensure_cursor_visible(pane_height=10, doc_width=80)

        # scroll_offset must advance so line 20 is within visible rows
        self.assertGreater(tui.scroll_offset, 0)
        self.assertLessEqual(tui.scroll_offset, 20)
        visible_count = sum(tui._visual_line_count(i, 80) for i in range(tui.scroll_offset, 21))
        self.assertLessEqual(visible_count, 10)

        # Jump to top ('g')
        tui.selected_line_idx = 0
        tui._ensure_cursor_visible(pane_height=10, doc_width=80)
        self.assertEqual(tui.scroll_offset, 0)

        # Jump to bottom ('G')
        tui.selected_line_idx = 99
        tui._ensure_cursor_visible(pane_height=10, doc_width=80)
        self.assertGreater(tui.scroll_offset, 85)
        visible_count_end = sum(tui._visual_line_count(i, 80) for i in range(tui.scroll_offset, 100))
        self.assertLessEqual(visible_count_end, 10)

    def test_less_navigation_half_page_scroll(self):
        from tui.app import ReviewAnchorTUI
        from tui.markdown_parser import MarkdownLine
        tui = ReviewAnchorTUI(plan_path="implementation_plan.md")

        tui.markdown_lines = [
            MarkdownLine(line_number=i, raw_text=f"Line {i}", line_type="text")
            for i in range(1, 51)
        ]
        tui.selected_line_idx = 0
        tui.scroll_offset = 0

        # Simulate 'd' (half page down in 20-row viewport -> step 8)
        half_screen = (20 - 4) // 2
        tui.selected_line_idx = min(len(tui.markdown_lines) - 1, tui.selected_line_idx + half_screen)
        tui._ensure_cursor_visible(pane_height=18, doc_width=80)
        self.assertEqual(tui.selected_line_idx, 8)

        # Simulate 'u' (half page up -> step 8)
        tui.selected_line_idx = max(0, tui.selected_line_idx - half_screen)
        tui.scroll_offset = max(0, tui.scroll_offset - half_screen)
        tui._ensure_cursor_visible(pane_height=18, doc_width=80)
        self.assertEqual(tui.selected_line_idx, 0)
        self.assertEqual(tui.scroll_offset, 0)


if __name__ == "__main__":
    unittest.main()

