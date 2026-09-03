# Review Anchor

Records a Q/A turn with a model — the prompt, the review comments anchored to
lines of the design doc, and the response — in a format that is plain text you
can write in vim, and that renders to a git commit message of the shape this
repo already uses.

No model API is contacted. The prompt leaves by clipboard, the response comes
back by clipboard, and the tool's job is the bookkeeping in between.

---

## The convention this has to fit

From `git log` on this repo, before any of this existed:

```text
gemini 3.8 flash high

do you see the git node tagged pending-push? The GitHub default branch is
staging, and, for posterity, origin/HEAD is currently that tag, with just the
(configurable) model name as the commit message. Integrate that UX.
```

So: **subject line is a short label** — by convention the model name, sometimes
a plain note like `manual change` — and **the body is the prompt, verbatim**.
The `pending-push` tag bookmarks the subject-only variant used for temporary
commits. That is the whole convention, and none of it changes.

What it does not record is the other half of the turn: what the model said
back, and which lines of the plan a review comment was about.

---

## The format

One markdown file per turn, in `reviews/`, numbered in turn order:

```text
reviews/0009-git-config.md
```

```markdown
---
model: claude opus 5
subject: git config          # optional; defaults to model
doc: implementation_plan.md
doc-rev: 7353a60             # git blob id of the doc when the anchors were made
date: 2026-09-03T11:25:08-07:00
state: open                  # open while drafting, closed once committed
commit: b94fde4              # set on import, or when the prompt was committed first
---

## @prompt

What you are asking for. Goes into the commit body exactly as typed.

## @anchors

@@ implementation_plan.md:31 §standard-commit-format-with-review-anchors @@
> <type>(<scope>): <short summary>
Conventional-commits subjects would break every commit already written.

## @response

What came back. Stays in this file; never enters the commit message.

## @notes

Private scratch. Never sent, never committed to the message.
```

Section headers are `## @name` at column zero, outside fenced code. Anything
else — including `##` headings inside a pasted prompt or response — is ordinary
content, so transcripts round-trip unmangled.

### Anchors

```text
@@ <path>:<line>[,<count>] [§<section-slug>] @@
> quoted line from the doc
> quoted line from the doc
the comment, one or more lines
```

The header borrows the unified-diff hunk marker; the `>` run is context in the
same sense `git apply` uses it. Those quoted lines are what make the anchor
durable: when the doc shifts, `./review verify --fix` finds the text again and
rewrites the line number. `doc-rev` is the doc's git blob id (computed without
shelling out, so it works on an uncommitted plan) and tells you whether the
anchors are worth re-checking at all.

`§slug` is the GitHub heading anchor of the enclosing section, so a comment
still points somewhere useful when the line numbers are hopeless.

### The commit message it renders to

```text
git config

This project is starting with a detour for the sake of completeness of
documentation. […]

@@ implementation_plan.md:31 §standard-commit-format-with-review-anchors @@
> <type>(<scope>): <short summary>
Conventional-commits subjects would break every commit already written.

Review-Doc: implementation_plan.md@7353a60
Review-Log: reviews/0009-git-config.md
```

Subject and prompt exactly as before; anchors and trailers are additive.
`Review-Doc` and `Review-Log` are ordinary git trailers, so
`git interpret-trailers` and `git log --grep='Review-Log: …'` both work.

Toggle **bare** mode (`b` in the TUI, `--bare` on the CLI) and the message
collapses to the subject line alone — the `pending-push` style, for temporary
commits on a moving branch.

### Why the response is not in the commit message

The commit message answers *what did I ask for*, which is what it has always
answered here, and it stays diffable and skimmable in `git log`. The exchange
file answers *and what came back*, is committed alongside the code the turn
produced, and can hold a full transcript without turning `git log` into a
scrollback buffer. The `Review-Log:` trailer is the link between them.

Git notes were the other candidate and lost: they do not push without extra
refspec configuration, they are awkward to edit by hand, and they are invisible
in every interface that matters here.

### Backwards compatibility

`Exchange.from_commit_message` is both the message parser and the history
importer, so compatibility is not a claim, it is the same code path:

```bash
./review import        # backfills reviews/ from git log
```

Every commit in this repo — prompt-in-the-body ones, the subject-only temporary
commit, the GitHub root commit — reads back as a valid exchange with an empty
response, and re-renders byte for byte. There is a test for it.

---

## Workflow

```text
   write the prompt, anchor comments on the plan        (TUI or $EDITOR)
   y  →  clipboard  →  paste into the chat
   … model answers …
   copy the answer  →  R  →  it lands in @response
   C  →  git add -A && git commit
```

Same loop in the browser view, with a font-size slider for lining the document
up against the Antigravity IDE review pane.

---

## Commands

```bash
./review                    # TUI on the current exchange
./review new "some title"   # start a turn
./review list               # the log
./review show 9             # print one exchange
./review message 9          # its commit message → git commit -F -
./review verify 9 --fix     # re-locate anchors after the doc moved
./review import             # backfill from git history
./review gui                # side-by-side web view on 127.0.0.1:8765
./review -f path/to/plan.md # a different design doc
```

`./review message` composing with `git commit -F -` is the escape hatch: the
tool never has to be in the loop for the commit itself.

## Keys

| | |
| --- | --- |
| `j k ↑ ↓ PgUp PgDn g G` | move · `#` goto line |
| `v` | range mark, to anchor several lines |
| `c` / `Enter` | comment on the line or range (empty input opens `$EDITOR`) |
| `d` / `x` | drop anchors on the line or range |
| `V` | verify anchors, relocate the ones the doc moved |
| `p` | paste from clipboard and jump to the matching line |
| `P` `r` `e` | edit prompt · response · the whole exchange file in `$EDITOR` |
| `R` | replace the response from the clipboard |
| `y` `Y` | copy prompt + anchors · copy the commit message |
| `m` `s` | set model label · commit subject |
| `b` | toggle bare commit (subject only) |
| `n` `[` `]` | new exchange · previous · next |
| `C` | `git add -A && git commit` |
| `1 2 3 4` | pane: commit · prompt · response · anchors (`J`/`K` scroll) |
| `Tab` `+` `-` | split pane · wrap width |
| `?` `q` | help · quit |

## Layout

```text
review-anchor/
  review_anchor.py     CLI
  server.py            local web view
  tui/
    exchange.py        the format — parse, render, commit-message round trip
    store.py           the reviews/ directory
    git_anchoring.py   git plumbing and history import
    markdown_parser.py doc → lines with types and heading slugs
    app.py             curses front end
    wysiwyg_renderer.py
    clipboard.py       pbcopy/pbpaste, wl-/xclip fallbacks, then a file
  tests/
  web/                 index.html · style.css · app.js
```

`exchange.py` and `store.py` are the whole format and import neither curses nor
git, which is what would make this portable into an OpenCode fork later.

Standard library only.

```bash
python3 -m unittest discover -s review-anchor/tests -p "test_*.py"
```
