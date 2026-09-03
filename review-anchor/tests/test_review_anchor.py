"""
Unit tests for Review Anchor.
Tests markdown parsing, comment anchoring, and backwards-compatible git commit formatting.
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
from tui.git_anchoring import GitAnchoring, ReviewComment


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

        # In model_only mode (pending-push style), commit message is strictly the model name
        msg = anchor.format_commit_message(general_prompt="Should be omitted in model_only")
        self.assertEqual(msg, "gemini 3.8 flash high")

        # Review body is available for Git Notes
        review_notes = anchor.format_review_body()
        self.assertIn("[Line 1]", review_notes)
        self.assertIn("Test comment", review_notes)

    def test_backwards_compatible_detailed_commit_format(self):
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

        # Body contains general prompt
        self.assertIn("Updated review comments on implementation plan.", commit_msg)

        # Body contains anchored line reference
        self.assertIn("[Line 5] Section: \"User Review Required\"", commit_msg)
        self.assertIn("Review: Approved. Ensure 60mm is verified with physical ruler.", commit_msg)

        # Body contains RFC 822 trailers
        self.assertIn("Review-Doc: implementation_plan.md", commit_msg)
        self.assertIn("Review-Anchor: #user-review-required", commit_msg)

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
        self.assertEqual(len(anchor1.get_comments()), 1)

        anchor2 = GitAnchoring(repo_root=self.temp_dir.name, plan_path=self.plan_path)
        self.assertEqual(len(anchor2.get_comments()), 1)
        self.assertEqual(anchor2.get_comments()[0].comment_text, "Test comment 1")


if __name__ == "__main__":
    unittest.main()
