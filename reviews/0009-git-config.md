---
model: claude opus 5
subject: git config
doc: implementation_plan.md
doc-rev: 7353a60
date: 2026-09-03T11:25:08-07:00
state: closed
commit: b94fde4
---

## @prompt

This project is starting with a detour for the sake of completeness of documentation. The commit message history of the current monorepo shows how I've been keeping the prompts and model response versions. I've had Gemini set up a TUI that inherits git conventions for design doc review comments in Antigravity IDE. Decide on a format that is compatible with the work so far which can document the Q/A interactions that Claude, then integrate that into the TUI as well. I haven't yet tried the interface and so am not attached to any particulars, revise as applicable. The TUI shouldn't touch model API endpoints yet: until there's a format I can reasonably read/write myself, I'm copy/pasting back and forth. Maybe some day it'll end up in an OpenCode fork. Don't ask any questions as a part of the response to this prompt.

## @anchors

@@ implementation_plan.md:31 §standard-commit-format-with-review-anchors @@
> <type>(<scope>): <short summary>
Superseded. The convention actually practised in this history puts a short
label on the subject line — by convention the model name — and the prompt
verbatim in the body. Conventional-commits subjects would break every commit
already written. The subject stays a free label; `subject:` in the exchange
file overrides the model name for turns like `manual change`.

@@ implementation_plan.md:36 §standard-commit-format-with-review-anchors @@
> Review-Anchor: #component-1-targetcore-shared-multi-platform-swift-package
One trailer can only name one section, so a review with four comments has
nowhere to put three of them. Replaced by `@@ file:line §slug @@` blocks in
the body — as many as the review needs, each carrying its own quoted context
so it can be relocated when the doc moves. `Review-Doc` survives, now pinned
to the doc's blob id; `Review-Log` is added, pointing at the exchange file.

## @response

Format: one markdown file per turn under `reviews/`, and the commit message is
derived from it rather than the other way round.

* `git log` keeps meaning exactly what it means today — subject is a short
  label, body is the prompt verbatim. Every existing commit parses as a valid
  exchange; `Exchange.from_commit_message` is both the reader and the importer,
  and `./review import` backfilled all nine commits to prove it.
* Anchored comments are `@@ path:line[,count] §slug @@` blocks: unified-diff
  header, `>` context lines quoting the doc, then the comment. They go in the
  commit body under the prompt, so a review reads in `git log` with no tooling.
* The quoted context is what makes anchors survive edits — `./review verify
  --fix` re-finds moved text and rewrites the line numbers, and `doc-rev`
  (the doc's git blob id) says whether that check is even needed.
* The response lives only in the exchange file, never in the commit message.
  The commit message answers "what did I ask for", which is what it has always
  answered; the file answers "and what came back".
* Trailers: `Review-Doc: <path>@<blob>` and `Review-Log: reviews/NNNN-*.md`.
  Both are ordinary git trailers, so `git interpret-trailers` and
  `git log --grep` still work.

TUI: rebuilt around the exchange rather than a loose comment list. Left pane is
the WYSIWYG doc with an anchor gutter and adjustable wrap width; right pane
tabs through prompt · anchors · response · commit. `y` copies prompt + anchors
out, `R` pastes the reply back, `V` verifies anchors, `C` commits. Multi-line
text hands off to `$EDITOR`, git-style. `e` opens the raw exchange file, since
the format is meant to be edited by hand as readily as by the tool.

No model API is called anywhere in the tool.

## @notes

The prompt for this turn was committed as b94fde4 before the work started, so
this file — the response and the anchors — lands in the following commit. That
is the normal shape when the prompt is committed up front; `commit:` records
where the prompt landed, `Review-Log:` on the next commit points back here.
