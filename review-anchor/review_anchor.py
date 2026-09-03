#!/usr/bin/env python3
"""
Review Anchor -- command line entry point.

    ./review                 open the TUI on the current exchange
    ./review new "title"     start a new exchange
    ./review list            list the exchange log
    ./review show 3          print one exchange
    ./review message 3       print its commit message (pipe to git commit -F -)
    ./review verify --fix    re-locate anchors after the doc moved
    ./review import          backfill reviews/ from existing git history
    ./review gui             side-by-side web view

No subcommand touches a model API; see review-anchor/README.md.
"""

import argparse
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from tui.exchange import Exchange, blob_rev  # noqa: E402
from tui.git_anchoring import Config, Git, import_history  # noqa: E402
from tui.markdown_parser import MarkdownParser  # noqa: E402
from tui.store import ReviewStore  # noqa: E402


def find_doc(repo_root: str, config: Config) -> str:
    """Locate the design doc under review."""
    candidates = [
        str(config["doc"]),
        os.path.join(repo_root, str(config["doc"])),
        "implementation_plan.md",
        os.path.join(repo_root, "implementation_plan.md"),
    ]
    for path in candidates:
        if path and os.path.exists(path):
            return os.path.abspath(path)
    brain = os.path.expanduser("~/.gemini/antigravity-ide/brain")
    plans = sorted(
        glob.glob(f"{brain}/*/implementation_plan.md"), key=os.path.getmtime, reverse=True
    )
    if plans:
        return plans[0]
    return os.path.join(repo_root, "implementation_plan.md")


def resolve(store: ReviewStore, number):
    ex = store.load(int(number)) if number else store.current() or store.latest()
    if ex is None:
        sys.exit("no exchanges yet; try: ./review new \"title\"")
    return ex


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="review", description=__doc__.strip().splitlines()[0])
    parser.add_argument("-f", "--file", dest="doc", help="design doc under review")
    parser.add_argument("-C", dest="repo", help="repository root")
    sub = parser.add_subparsers(dest="cmd")

    sub.add_parser("tui", help="open the terminal UI (default)")

    gui = sub.add_parser("gui", help="side-by-side web view")
    gui.add_argument("--port", type=int, default=8765)
    gui.add_argument("--no-browser", action="store_true")

    new = sub.add_parser("new", help="start a new exchange")
    new.add_argument("title", nargs="*", help="short title, used for the filename")

    sub.add_parser("list", help="list the exchange log")

    show = sub.add_parser("show", help="print an exchange")
    show.add_argument("number", nargs="?")

    msg = sub.add_parser("message", help="print the commit message for an exchange")
    msg.add_argument("number", nargs="?")
    msg.add_argument("--bare", action="store_true", help="subject only (pending-push style)")

    ver = sub.add_parser("verify", help="check anchors still point at the quoted text")
    ver.add_argument("number", nargs="?")
    ver.add_argument("--fix", action="store_true", help="rewrite line numbers that moved")

    imp = sub.add_parser("import", help="backfill reviews/ from git history")
    imp.add_argument("--limit", type=int, default=0)
    imp.add_argument("--range", dest="rev_range", default="HEAD")

    args, extra = parser.parse_known_args(argv)
    # `./review path/to/plan.md` still works.
    for token in extra:
        if os.path.exists(token) and not args.doc:
            args.doc = token
        else:
            parser.error(f"unrecognised argument: {token}")

    repo_root = os.path.abspath(args.repo) if args.repo else Git.discover_root()
    config = Config(repo_root)
    doc = os.path.abspath(args.doc) if args.doc else find_doc(repo_root, config)
    store = ReviewStore(repo_root)
    git = Git(repo_root)

    cmd = args.cmd or "tui"

    if cmd == "new":
        title = " ".join(args.title)
        ex = store.create(model=str(config["model"]), doc=os.path.relpath(doc, repo_root), title=title)
        print(store.rel(ex.path))
        return 0

    if cmd == "list":
        for number, path in store.entries():
            ex = Exchange.load(path)
            first = (ex.prompt.splitlines() or [""])[0][:48]
            flag = "·" if ex.state == "closed" else "○"
            print(f"{flag} {number:04d}  {ex.model[:24]:24}  {len(ex.anchors):2d}⚓  {first}")
        return 0

    if cmd == "show":
        print(resolve(store, args.number).dumps(), end="")
        return 0

    if cmd == "message":
        ex = resolve(store, args.number)
        print(
            ex.commit_message(
                log_path=store.rel(ex.path),
                extra_trailers=config.extra_trailers,
                bare=args.bare or bool(config["bare_commit"]),
            ),
            end="",
        )
        return 0

    if cmd == "verify":
        ex = resolve(store, args.number)
        doc_path = os.path.join(repo_root, ex.doc) if ex.doc else doc
        lines = [l.raw_text for l in MarkdownParser.parse_file(doc_path)]
        moved = lost = 0
        for anchor in ex.anchors:
            if anchor.matches(lines):
                continue
            found = anchor.relocate(lines)
            if found and args.fix:
                print(f"  moved {anchor.path}:{anchor.line} → {found}")
                anchor.line = found
                moved += 1
            elif found:
                print(f"  stale {anchor.path}:{anchor.line} (now at {found})")
                moved += 1
            else:
                print(f"  lost  {anchor.path}:{anchor.line} — quoted text is gone")
                lost += 1
        total, name = len(ex.anchors), os.path.basename(doc_path)
        if args.fix:
            ex.meta["doc-rev"] = blob_rev(doc_path)
            ex.save()
            print(f"{total - lost}/{total} anchors resolved against {name} ({moved} relocated)")
            return 1 if lost else 0
        print(f"{total - moved - lost}/{total} anchors verified against {name}")
        return 1 if (moved or lost) else 0

    if cmd == "import":
        written = import_history(git, store, limit=args.limit, rev_range=args.rev_range)
        for path in written:
            print(store.rel(path))
        if not written:
            print("nothing to import")
        return 0

    if cmd == "gui":
        from server import start_gui_server

        start_gui_server(
            doc_path=doc, repo_root=repo_root, port=args.port, open_browser=not args.no_browser
        )
        return 0

    from tui.app import ReviewAnchorTUI

    ReviewAnchorTUI(plan_path=doc, repo_root=repo_root).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
