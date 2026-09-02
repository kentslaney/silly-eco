#!/usr/bin/env python3
"""
Review Anchor CLI & Launcher.
Anchors review comments to implementation plans and generates
backwards-compatible git commit messages.
"""

import argparse
import glob
import os
import sys

# Ensure local packages are importable
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

from tui.app import ReviewAnchorTUI
from server import start_gui_server


def find_default_plan() -> str:
    """Auto-locate the most relevant implementation_plan.md."""
    # 1. Check local directory
    if os.path.exists("implementation_plan.md"):
        return "implementation_plan.md"

    # 2. Check parent directory
    parent_plan = os.path.join(os.path.dirname(current_dir), "implementation_plan.md")
    if os.path.exists(parent_plan):
        return parent_plan

    # 3. Check ~/.gemini/antigravity-ide/brain/*/implementation_plan.md
    home_brain = os.path.expanduser("~/.gemini/antigravity-ide/brain")
    if os.path.exists(home_brain):
        plans = glob.glob(f"{home_brain}/*/implementation_plan.md")
        if plans:
            # Pick newest by modification time
            plans.sort(key=lambda p: os.path.getmtime(p), reverse=True)
            return plans[0]

    return "implementation_plan.md"


def main():
    parser = argparse.ArgumentParser(
        description="Review Anchor: WYSIWYG review comment anchoring and git commit generator."
    )
    parser.add_argument(
        "plan_file",
        nargs="?",
        default=None,
        help="Path to implementation_plan.md (defaults to auto-discovered plan)"
    )
    parser.add_argument(
        "--gui",
        action="store_true",
        help="Launch the side-by-side Web GUI in your browser instead of the terminal TUI"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8765,
        help="Port for Web GUI server (default: 8765)"
    )
    parser.add_argument(
        "--no-browser",
        action="store_true",
        help="Do not auto-open browser in GUI mode"
    )

    args = parser.parse_args()

    plan_path = args.plan_file or find_default_plan()
    repo_root = os.path.dirname(current_dir) if os.path.basename(current_dir) == "review-anchor" else os.getcwd()

    if not os.path.exists(plan_path):
        print(f"Notice: Plan file '{plan_path}' does not exist yet. Creating a placeholder.")
        with open(plan_path, "w", encoding="utf-8") as f:
            f.write("# Implementation Plan\n\n> [!NOTE]\n> Ready for review.\n")

    print(f"⚓ Review Anchor loaded with: {plan_path}")

    if args.gui:
        start_gui_server(
            plan_path=os.path.abspath(plan_path),
            repo_root=os.path.abspath(repo_root),
            port=args.port,
            open_browser=not args.no_browser
        )
    else:
        app = ReviewAnchorTUI(
            plan_path=os.path.abspath(plan_path),
            repo_root=os.path.abspath(repo_root)
        )
        app.run()


if __name__ == "__main__":
    main()
