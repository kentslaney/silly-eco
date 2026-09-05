# Review Anchor

A pure Lua review comment anchoring layer and runtime wrapper for Neovim, featuring Org-mode-inspired document structure, Git Notes `diff -p` context anchors, Claude Code Q/A snapshot integration, and native Git commit generation for the `silly-eco` monorepo.

Review Anchor enables seamless pair-review between human reviewers and AI models (Antigravity IDE Gemini & Claude Code), maintaining a principled separation of concerns between commit messages and Git Notes:
- **Commit Message as Historical Model Input Snapshot**: Review comments, instructions, prompts, and Claude Code Q/A pairs are historical snapshots of contextual instructions given to the model. They belong in the commit message body under the model header (tagged with reference identifiers like `[Ref 1]`, `[Ref 2]`), keeping historical records immutable without generating throwaway markdown files per commit.
- **Git Notes for Rebase-Tolerant `diff -p` Context Anchors**: Line anchors and document locations shift when rebases or operational transformations (OT) occur. Git Notes attach each reference number (`[Ref 1]`, `[Ref 2]`) to its `diff -p` type context (`@@ ## Enclosing Heading / Symbol @@`, line number, and context hunk), enabling anchors to be tracked and updated independently of immutable commit SHAs.
- **Claude Code Q/A Format**: Conversational prompt instructions formatted with Unicode bullet point and right arrow (`• Question → Answer`), treated as direct model input context without artificial design doc references or Git Notes anchors.
- **Org-mode Addon Layer for Neovim**: Uses the user's native Neovim runtime (`~/.config/nvim`) without disabling user configs or plugins, providing headline folding (`<Tab>`, `<S-Tab>`), visual range / sub-line anchoring, floating capture buffers (`<leader>rc`, `<leader>rq`, `<leader>rp`), and extmark virtual text badges.
- **Startup Split**: Opens `git log --graph --all` in a split below the normal editing buffer.

---

## Features

- **Native Neovim Runtime Wrapper (`./review`)**:
  - Automatically loads the `review_anchor` Lua plugin into the user's existing Neovim configuration.
  - Full native Vim editing: visual mode selections, sub-line and multi-line anchoring, motions (`M`, `zz`, `g`, `G`), undo/redo, and user plugins.
- **Initial Startup Split & Soft-Wrap**:
  - Normal buffer on top (the review document) with soft-wrapping (`wrap`, `linebreak`, `breakindent`) enabled.
  - Horizontal split below displaying `git log --graph --all --decorate` with full multi-line entries (ANSI colors).
  - Focus remains immediately in the upper buffer.
- **Org-Mode Outline & Folding**:
  - `<Tab>`: Cycle fold state for current heading (folded $\to$ children $\to$ expanded).
  - `<S-Tab>`: Cycle global outline levels document-wide (all folded $\to$ H1 $\to$ H2 $\to$ open all).
  - `]]` / `[[`: Jump to next / previous section heading.
  - `<leader>rx` or `<C-c><C-c>`: Toggle markdown checkbox (`- [ ]` $\leftrightarrow$ `- [x]`).
- **Review Anchoring & Extmarks**:
  - `<leader>rc` or `<leader>c` (Normal): Attach comment to current line.
  - `<leader>rc` or `<leader>c` (Visual): Attach comment to exact character range or visual block.
  - Renders gutter badge (`★ Ref N`) and inline virtual text (`[Ref N: "comment snippet..."]`).
  - Extmarks automatically follow line shifts as the document is edited.
- **Claude Code Q/A & Prompt Capture**:
  - `<leader>rq`: Floating capture window for structured `Q:` and `A:` pairs.
  - `<leader>rp`: Floating capture window for general model prompts / instructions.
- **Git Notes & Commit Generator**:
  - Backwards-compatible model name subject (e.g. `gemini 3.8 flash high` or `[blank] gemini 3.8 flash high`).
  - RFC 822 trailers (`Review-Doc`, `Review-Anchor`, `Reviewed-By`, `Review-Status`, `Reviewed-At`).
  - `<leader>rP`: Preview formatted commit message and Git Notes (supports `[b]` toggle in preview).
  - `<leader>ry` / `<leader>rn`: Copy commit message / Git Notes to macOS clipboard.
  - `<leader>rC`: Stages all changes (`git add -A`), commits, and attaches Git Notes to `HEAD`.
  - `<leader>rb`: Toggle `[blank] ` prefix on model name for starting new conversations.
  - `<leader>rt`: Toggle between `detailed` snapshot mode and `model_only` mode.
  - `<leader>rm`: Configure active AI model name.

---

## Quick Start

Run the wrapper from the monorepo root:
```bash
./review
```
Or specify a document to review:
```bash
./review path/to/implementation_plan.md
```

---

## Keybindings Summary

| Keybinding | Mode | Action |
| --- | --- | --- |
| `<Tab>` | Normal | Cycle fold for current heading subtree |
| `<S-Tab>` | Normal | Cycle global fold levels document-wide |
| `]]` / `[[` | Normal | Jump to next / previous section heading |
| `<leader>rc` / `<leader>c` | Normal | Add review comment on current line |
| `<leader>rc` / `<leader>c` | Visual | Add review comment on selected text / range |
| `<leader>rq` | Normal | Add Claude Code Q/A item (prompt snapshot) |
| `<leader>rp` | Normal | Edit general model prompt / instruction |
| `<leader>rd` | Normal | Delete review anchor under cursor |
| `<leader>re` | Normal | Edit comment on current anchor |
| `<leader>rx` / `<C-c><C-c>` | Normal | Toggle checkbox item (`- [ ]` $\leftrightarrow$ `- [x]`) |
| `<leader>rg` | Normal | Toggle `git log --graph --all` split below |
| `<leader>rP` | Normal | Preview formatted Git Commit message & Git Notes (`[b]` to toggle blank) |
| `<leader>ry` | Normal | Copy Git Commit message to system clipboard |
| `<leader>rn` | Normal | Copy Git Notes payload to system clipboard |
| `<leader>rC` | Normal | Stage all changes (`git add -A`), execute Git Commit, attach Git Notes |
| `<leader>rb` | Normal | Toggle `[blank] ` prefix on model name (denotes new conversation) |
| `<leader>rm` | Normal | Change AI model name |
| `<leader>rt` | Normal | Toggle commit mode (`detailed` vs `model_only`) |
| `<leader>r?` / `<leader>rh` | Normal | Show keybinding cheatsheet |

---

## Commit & Git Notes Format

### 1. Git Commit Message (Snapshot of Model Input)
```text
gemini 3.8 flash high

Approved plan with operational transformation updates.

Claude Code Q/A Context:
• How should error correction handle camera tilt exceeding 45°? → Reject frame with haptic guidance to re-orient.

Reviewed implementation_plan.md:

[Ref 1] Review on "User Review Required":
> "> The corner lines must be 60mm long."
Review: Approved. Ensure 60mm is verified with physical ruler.

Review-Doc: implementation_plan.md
Review-Anchor: #user-review-required
Reviewed-By: Kent Slaney <kent@slaney.org>
Review-Status: Approved
Reviewed-At: 2026-09-05T12:00:00Z
```

### 2. Git Notes (`refs/notes/commits` - Rebase-Tolerant `diff -p` Anchors)
```text
Review Anchors (diff -p context):

[Ref 1] implementation_plan.md:L7
Context: @@ ## User Review Required @@
Hunk:
  > [!IMPORTANT]
  > The corner lines must be 60mm long.
```

---

## Running Tests

Run the headless Neovim test suite:
```bash
./review-anchor/tests/run_tests.sh
```
Or run individual tests:
```bash
nvim --headless -l review-anchor/tests/test_diff_p.lua
nvim --headless -l review-anchor/tests/test_git_notes.lua
nvim --headless -l review-anchor/tests/test_anchors.lua
nvim --headless -l review-anchor/tests/test_startup.lua
```
