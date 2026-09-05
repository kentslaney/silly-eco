# Review Anchor (`silly-eco`)

A pure Lua review comment anchoring layer and standalone Neovim plugin, featuring Org-mode-inspired document structure, Git Notes `diff -p` context anchors, Claude Code Q/A snapshot integration, interactive repository initialization splash screen, and native Git commit generation.

Review Anchor enables seamless pair-review between human reviewers and AI models (Antigravity IDE Gemini & Claude Code), maintaining a principled separation of concerns between commit messages and Git Notes:
- **Commit Message as Historical Model Input Snapshot**: Review comments, instructions, prompts, and Claude Code Q/A pairs are historical snapshots of contextual instructions given to the model. They belong in the commit message body under the model header (tagged with reference identifiers like `[Ref 1]`, `[Ref 2]`), keeping historical records immutable without generating throwaway markdown files per commit.
- **Git Notes for Rebase-Tolerant `diff -p` Context Anchors**: Line anchors and document locations shift when rebases or operational transformations (OT) occur. Git Notes attach each reference number (`[Ref 1]`, `[Ref 2]`) to its `diff -p` type context (`@@ ## Enclosing Heading / Symbol @@`, line number, and context hunk), enabling anchors to be tracked and updated independently of immutable commit SHAs.
- **Claude Code Q/A Format**: Conversational prompt instructions formatted with Unicode bullet point and right arrow (`• Question → Answer`), treated as direct model input context without artificial design doc references or Git Notes anchors.
- **Org-mode Addon Layer for Neovim**: Uses your native Neovim runtime without disabling user configs or plugins, providing headline folding (`<Tab>`, `<S-Tab>`), visual range / sub-line anchoring, floating capture buffers (`<leader>rc`, `<leader>rq`, `<leader>rp`), and extmark virtual text badges.
- **Git Log Split (Off by Default)**: The bottom `git log --graph --all` split is kept off by default to maintain a clean workspace and can be toggled on/off at any time with `<leader>rl` or `:ReviewLog`.
- **Repository Setup Splash Screen (`<leader>rI` / `:ReviewInit`)**: Interactive floating setup splash screen for the current working directory to configure remote repository URLs, select licenses (CC0, MIT, GPL, Apache, BSD, Unlicense), create initial commits, and stage `.gitignore`.

---

## Installation

You can install `review-anchor` using your favorite Neovim package manager:

### `lazy.nvim`
```lua
{
  "kentslaney/silly-eco",
  cmd = { "Review", "ReviewInit", "ReviewLog", "ReviewModelCommit" },
  keys = {
    { "<leader>ri", desc = "Review Anchor: Inline Instructions" },
    { "<leader>rI", desc = "Review Anchor: Repository Setup Splash Screen" },
    { "<leader>rl", desc = "Review Anchor: Toggle Git Log Split" },
    { "<leader>rc", desc = "Review Anchor: Add Review Comment" },
    { "<leader>rC", desc = "Review Anchor: Commit Changes & Attach Notes" },
    { "<leader>rM", desc = "Review Anchor: Commit Model Only" },
    { "<leader>rp", desc = "Review Anchor: Prompt Capture" },
    { "<leader>rq", desc = "Review Anchor: Claude Q/A Context" },
    { "<leader>r?", desc = "Review Anchor: Cheatsheet" },
  },
  opts = {
    show_git_log = false, -- keep bottom git log split off by default (toggle via <leader>rl)
    model_name = "gemini 3.8 flash high",
    commit_mode = "detailed", -- "detailed" or "model_only"
  },
}
```

### `packer.nvim`
```lua
use({
  "kentslaney/silly-eco",
  config = function()
    require("review_anchor").setup({
      show_git_log = false,
      model_name = "gemini 3.8 flash high",
    })
  end,
})
```

### `vim-plug`
```vim
Plug 'kentslaney/silly-eco'

" In init.lua:
" require('review_anchor').setup({ show_git_log = false })
```

---

## Features

- **Standard Neovim Plugin & CLI Wrapper (`./review`)**:
  - Works either as a native Neovim plugin in your existing setup, or via the bundled `./review` wrapper script.
  - Full native Vim editing: visual mode selections, sub-line and multi-line anchoring, motions (`M`, `zz`, `g`, `G`), undo/redo, and user plugins.
- **Clean Layout & Soft-Wrap**:
  - Normal buffer on top with soft-wrapping (`wrap`, `linebreak`, `breakindent`) enabled.
  - Git log split is kept **off by default**; toggled on demand via `<leader>rl` or `:ReviewLog`.
  - When starting without an implementation plan file (`./review` or `:Review`), opens inline instructions without any blank split left behind.
- **Repository Setup Splash Screen (`<leader>rI` / `:ReviewInit`)**:
  - Centered interactive modal for the current working directory (`cwd`).
  - Displays current git status, branch, remote origin, and license options.
  - Hotkeys: `r` to set/edit remote URL, `1`-`7` to select license (`CC0-1.0`, `MIT`, `GPL-3.0`, `Apache-2.0`, `BSD-3-Clause`, `Unlicense`, `None`), and `<CR>`/`i` to initialize.
- **Inline Instructions Split (`<leader>ri`)**:
  - Opens an instructions buffer above the git log graph if open, or in the current window.
  - Like git rebase: quitting without saving (`:q!`, `ZQ`, `<C-c><C-k>`) cancels the operation; quitting with saving (`:wq`, `ZZ`, `<C-c><C-c>`) stages all changes (`git add -A`), commits with the instructions, and refreshes the git log graph.
  - Opening the floating model prompt window (`<leader>rp`) pulls the inline instruction content, closes that split temporarily, and restores it updated upon closing.
- **Org-Mode Outline & Folding**:
  - `<Tab>`: Cycle fold state for current heading (folded $\to$ children $\to$ expanded).
  - `<S-Tab>`: Cycle global outline levels document-wide (all folded $\to$ H1 $\to$ H2 $\to$ open all).
  - `]]` / `[[`: Jump to next / previous section heading.
  - `<leader>rx` or `<C-c><C-c>`: Toggle markdown checkbox (`- [ ]` $\leftrightarrow$ `- [x]`).
- **Review Anchoring & Extmarks**:
  - `<leader>rc` (Normal): Attach comment to current line.
  - `<leader>rc` (Visual): Attach comment to exact character range or visual block.
  - Renders gutter badge (`★ Ref N`) and inline virtual text (`[Ref N: "comment snippet..."]`).
  - Extmarks automatically follow line shifts as the document is edited.
- **Claude Code Q/A & Prompt Capture**:
  - `<leader>rq`: Floating capture window for structured `Q:` and `A:` pairs.
  - `<leader>rp`: Floating capture window for general model prompts / instructions.
- **Git Notes & Commit Generator**:
  - Model name subject header (e.g. `gemini 3.8 flash high` or `[blank] gemini 3.8 flash high`).
  - RFC 822 trailers (`Review-Doc`, `Review-Anchor`, `Reviewed-By`, `Review-Status`, `Reviewed-At`) and Git Notes are included **only when comments exist**, keeping prompt-only commits clean.
  - `<leader>rP`: Preview formatted commit message and Git Notes (supports `[b]` toggle in preview).
  - `<leader>ry` / `<leader>rn`: Copy commit message / Git Notes to macOS clipboard.
  - `<leader>rM`: Commit changes with just the active model name.
  - `<leader>rC`: Stage all changes (`git add -A`), execute Git Commit, attach Git Notes.
  - **Smart Amend**: If instructions or review is committed without changes and HEAD is the current model name, it automatically uses `git commit --amend` to add the instructions into HEAD instead of making a new commit.
  - `<leader>rb`: Toggle `[blank] ` prefix on model name for starting new conversations.
  - `<leader>rt`: Toggle between `detailed` snapshot mode and `model_only` mode.
  - `<leader>rm`: Configure active AI model name.

---

## User Commands

| Command | Description |
| --- | --- |
| `:Review [file]` | Start Review Anchor session (opens target file or inline instructions) |
| `:ReviewInit [dir]` | Open repository initialization splash screen for directory (default: `cwd`) |
| `:ReviewLog` | Toggle bottom `git log --graph --all` split |
| `:ReviewModelCommit` | Stage all changes and commit with just the AI model name |

---

## Keybindings Summary (Strictly `<leader>r` Prefix)

| Keybinding | Mode | Action |
| --- | --- | --- |
| `<Tab>` | Normal | Cycle fold for current heading subtree |
| `<S-Tab>` | Normal | Cycle global fold levels document-wide |
| `]]` / `[[` | Normal | Jump to next / previous section heading |
| `<leader>ri` | Normal | Open inline instructions split (`:wq` to commit, `:q!` to cancel) |
| `<leader>rI` / `<leader>rs` | Normal | Open repository initialization splash screen for `cwd` |
| `<leader>rl` / `<leader>rg` | Normal | Toggle `git log --graph --all` split below (off by default) |
| `<leader>rc` | Normal | Add review comment on current line |
| `<leader>rc` | Visual | Add review comment on selected text / range |
| `<leader>rq` | Normal | Add Claude Code Q/A item (prompt snapshot) |
| `<leader>rp` | Normal | Edit general model prompt / instruction |
| `<leader>rd` | Normal | Delete review anchor under cursor |
| `<leader>re` | Normal | Edit comment on current anchor |
| `<leader>rx` / `<C-c><C-c>` | Normal | Toggle checkbox item (`- [ ]` $\leftrightarrow$ `- [x]`) |
| `<leader>rP` | Normal | Preview formatted Git Commit message & Git Notes (`[b]` to toggle blank) |
| `<leader>ry` | Normal | Copy Git Commit message to system clipboard |
| `<leader>rn` | Normal | Copy Git Notes payload to system clipboard |
| `<leader>rM` | Normal | Commit changes with just model name |
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

Run the full headless Neovim test suite:
```bash
./tests/run_tests.sh
```
Or run individual tests:
```bash
nvim --headless -l tests/test_diff_p.lua
nvim --headless -l tests/test_git_notes.lua
nvim --headless -l tests/test_anchors.lua
nvim --headless -l tests/test_startup.lua
nvim --headless -l tests/test_inline.lua
nvim --headless -l tests/test_repo_init.lua
nvim --headless -l tests/test_splash.lua
```
