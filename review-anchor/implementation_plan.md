# Review Anchor: Pure Lua Neovim Wrapper & Org-Mode Addon Layer

Restart and rebuild `review-anchor` as a pure Lua Neovim plugin and runtime wrapper (`./review`). This architecture replaces the previous Python curses implementation with the user's native Neovim runtime, attaching an Org-mode-inspired review layer for outline navigation, sub-line and multi-line visual anchoring, Claude Code Q/A contextual prompts, Git Notes `diff -p` context management, and an initial layout featuring `git log --graph --all` in a split below a normal buffer.

---

## User Review Required

> [!IMPORTANT]
> **Wrapper Execution Model**:
> The entry command `./review [file]` executes the user's installed `nvim` binary (`/opt/homebrew/bin/nvim`), prepending the plugin directory to `runtimepath` without suppressing user configs (`~/.config/nvim/init.lua`). The user's custom plugins, themes, and personal keymaps remain active while the review addon layer binds custom buffer-local mappings and extmarks.

> [!NOTE]
> **Initial Split Layout**:
> When launched, the tool opens the target document in the upper normal buffer and immediately opens a horizontal split below showing `git log --graph --all` (rendered with ANSI colors via terminal or buffer job), keeping cursor focus in the upper buffer.

---

## Key Architecture & Org-Mode Comparison

| Org-Mode Feature (Emacs) | Review-Anchor Lua Addon (Neovim) |
| --- | --- |
| **Headline Folding & Cycling** | `<Tab>` / `<S-Tab>` toggles fold cycles (`folded` $\to$ `children` $\to$ `expanded`) on Markdown `#`, `##`, `###` headings. |
| **Outline Motions** | `]]` and `[[` jump between section headings across the document. |
| **Quick Capture (`org-capture`)** | Floating capture buffer for review comments (`<leader>rc` / `c`), Claude Q/A (`<leader>rq`), and general model prompts (`<leader>rp`). |
| **Visual & Sub-line Anchoring** | Visual mode selection (`v` / `V`) allows anchoring comments to specific character spans or multi-line blocks. |
| **Metadata Drawers / Overlays** | Neovim Extmarks (`nvim_buf_set_extmark`) display `[Ref N]` badges and virtual text annotations without altering buffer content. |
| **Status / Checkbox Cycling** | `<leader>rx` or `<C-c><C-c>` toggles checkbox items (`[ ]` $\leftrightarrow$ `[x]`). |
| **Model Input Snapshot** | Commit message body records prompts, Claude Q/A pairs, and `[Ref N]` review comments with RFC 822 trailers. |
| **`diff -p` Git Notes** | Independent storage in `refs/notes/commits` linking `[Ref N]` to `@@ ## Section @@` and surrounding hunk snippets. |

---

## Proposed File Structure

```
review                                   # Executable wrapper script (Bash)
review-anchor/
├── lua/
│   └── review_anchor/
│       ├── init.lua                     # Entry point: setup(), start(filepath)
│       ├── config.lua                   # Config defaults, highlights, keybindings
│       ├── outline.lua                  # Org-mode style heading folding & navigation
│       ├── capture.lua                  # Floating capture buffer for comments & Q/A
│       ├── anchors.lua                  # In-memory anchor store, extmarks, virtual text
│       ├── diff_p.lua                   # diff -p context resolution (@@ ## Section @@)
│       ├── git.lua                      # Commit message & Git Notes formatting and execution
│       └── splits.lua                   # Split window management (git log split below)
├── tests/
│   ├── test_diff_p.lua                  # Tests for diff -p context parsing
│   ├── test_git_notes.lua               # Tests for commit & notes formatting
│   ├── test_anchors.lua                 # Tests for extmarks & anchor references
│   └── run_tests.sh                     # Headless test runner (nvim --headless -l)
└── README.md                            # Comprehensive usage and keybinding guide
```

---

## Proposed Changes

### Component 1: CLI Wrapper Command

#### [NEW] [review](file:///Users/kds/Documents/antigravity/silly-eco/review)
- Executable bash wrapper at repository root (`chmod +x review`).
- Usage: `./review [path/to/document.md]` (defaults to `implementation_plan.md` or a scratch buffer).
- Launches `nvim` with:
  ```bash
  exec nvim \
    --cmd "set rtp^=$SCRIPT_DIR/review-anchor" \
    -c "lua require('review_anchor').start('$TARGET_FILE')" \
    "$TARGET_FILE"
  ```
- Retains user's Neovim configurations and plugins while attaching `review_anchor`.

---

### Component 2: Core Lua Plugin (`review-anchor/lua/review_anchor/`)

#### [NEW] [init.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/init.lua)
- Defines `M.setup(opts)` and `M.start(filepath)`.
- Orchestrates:
  1. Setting up highlights and keymaps.
  2. Opening the target file in the upper window.
  3. Opening the bottom split with `git log --graph --all` via `splits.open_git_log()`.
  4. Initializing Org-mode outline folding and extmark tracking on the review buffer.
  5. Returning cursor focus to the upper review buffer.

#### [NEW] [config.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/config.lua)
- Default configuration table:
  - Model name: defaults to `gemini 3.8 flash high`.
  - Commit mode: `detailed` (model input snapshot) or `model_only` (temporary commit).
  - Git log command: `git log --graph --all --oneline --decorate --color=always`.
  - Split height: 35% of total editor height.
  - Reviewer identity: derived from `git config user.name` and `git config user.email`.
  - Highlight groups: custom highlights for `[Ref N]` badges, virtual text notes, and outline headers.

#### [NEW] [splits.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/splits.lua)
- Implements `open_git_log(opts)`:
  - Creates horizontal split below the current window: `vim.cmd("botright split")` with calculated height.
  - Sets up the split buffer:
    - Launches `:terminal git log --graph --all` or reads command output into a non-editable scratch buffer (`buftype=nofile`, `bufhidden=wipe`, `swapfile=false`).
    - Configures keybindings inside git log buffer: `q` to close, `<CR>` to inspect commit, `<C-w>k` to jump back to document.
  - Switches focus back to the top review buffer: `vim.api.nvim_set_current_win(main_win)`.
- Implements toggle function `toggle_git_log()` to hide or reopen the git log split.

#### [NEW] [outline.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/outline.lua)
- Org-mode style outline navigation and folding:
  - Custom foldexpr for Markdown (`#`, `##`, `###`, etc.).
  - `cycle_fold()` bound to `<Tab>`:
    - If folded $\to$ expand immediate children.
    - If expanded $\to$ fold subtree.
  - `cycle_global_fold()` bound to `<S-Tab>`:
    - Cycles all folds document-wide (all folded $\to$ top-level only $\to$ fully unfolded).
  - Outline motions: `]]` to jump to next heading, `[[` to jump to previous heading.
  - Checkbox toggle: `<leader>rx` or `<C-c><C-c>` toggles `- [ ]` to `- [x]`.

#### [NEW] [anchors.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/anchors.lua)
- Anchor management:
  - Stores anchors in buffer-local state:
    - `ref_id`: incremental integer (`1`, `2`, ...).
    - `line`: 0-indexed line number.
    - `col_start` / `col_end`: character range for visual selections.
    - `selected_text`: text snippet covered by the anchor.
    - `comment`: review comment content.
    - `diff_context`: enclosing heading/symbol context (`@@ ## Heading @@`).
    - `hunk`: surrounding lines.
  - Neovim Extmarks (`nvim_create_namespace("review_anchor")`):
    - Placed with `right_gravity = true` so line movements during editing automatically update anchor coordinates.
    - Renders gutter signs (`★ Ref N`) and inline virtual text (`[Ref N: "comment snippet..."]`).
  - Methods: `add_anchor()`, `delete_anchor()`, `get_anchors()`, `clear_anchors()`.

#### [NEW] [capture.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/capture.lua)
- Org-capture style floating window:
  - Opens a centered floating scratch window (`nvim_open_win`) with a rounded border.
  - Modes:
    1. **Comment Capture**: prompt for comment on current line or visual selection. Displays selected text in header.
    2. **Claude Code Q/A Capture**: prompt for Question and Answer strings.
    3. **Model Prompt Capture**: prompt for general instructions or prompt snapshot.
  - Editing keymaps within capture buffer:
    - `<C-s>` or `:w` or `<CR>`: save and attach anchor.
    - `<Esc>` or `q`: cancel capture.
  - Provides normal Vim editing (insert mode, undo, visual selections).

#### [NEW] [diff_p.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/diff_p.lua)
- Simulates Git's `diff -p` context search in pure Lua:
  - Given a target line in a buffer, scans upwards for the nearest heading (`^#+ .*`) or function/type signature.
  - Generates context header: `@@ ## <Section Title> @@`.
  - Extracts hunk context (3 lines before and after anchor line).
  - Computes relative file path from Git repository root.

#### [NEW] [git.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/git.lua)
- **Commit Message Formatter**:
  - Subject line: `<model_name>` (e.g. `gemini 3.8 flash high`).
  - Body:
    - General model prompt / instructions.
    - Claude Code Q/A section (tagged `[Ref N]`).
    - Review comments section (tagged `[Ref N]`, quoting reviewed line/snippet).
    - RFC 822 trailers (`Review-Doc`, `Review-Anchor`, `Reviewed-By`, `Reviewed-At`).
  - In `model_only` mode: subject is only `<model_name>`.
- **Git Notes Formatter**:
  - Generates `diff -p` payload for `refs/notes/commits`:
    - File path, `diff -p` context (`@@ ## Heading @@`), line number, and snippet hunk for each `[Ref N]`.
- **Git Actions**:
  - Copy commit message to clipboard (`vim.fn.setreg('+', msg)`).
  - Copy Git Notes payload to clipboard (`vim.fn.setreg('+', notes)`).
  - Preview window: opens floating split showing generated commit message & Git Notes.
  - Execute commit: runs `git commit -m ...` and `git notes add -f -m ... HEAD`.

---

### Component 3: Test Suite & Documentation

#### [NEW] [test_diff_p.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/tests/test_diff_p.lua)
- Tests `diff -p` heading resolution and hunk snippet extraction.

#### [NEW] [test_git_notes.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/tests/test_git_notes.lua)
- Tests format of commit message (model input snapshot with `[Ref N]`) and Git Notes.
- Tests Claude Code Q/A formatting.

#### [NEW] [test_anchors.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/tests/test_anchors.lua)
- Tests anchor creation, extmark rendering, and line tracking.

#### [NEW] [run_tests.sh](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/tests/run_tests.sh)
- Runs headless Neovim test suite:
  ```bash
  nvim --headless -l review-anchor/tests/test_diff_p.lua
  nvim --headless -l review-anchor/tests/test_git_notes.lua
  nvim --headless -l review-anchor/tests/test_anchors.lua
  ```

#### [MODIFY] [README.md](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/README.md)
- Updated documentation covering the pure Lua architecture, keybindings, org-mode features, and usage instructions.

---

## Keybindings Summary

| Keybinding | Action |
| --- | --- |
| `<Tab>` | Cycle fold for current heading subtree |
| `<S-Tab>` | Cycle global fold levels document-wide |
| `]]` / `[[` | Jump to next / previous section heading |
| `<leader>rc` / `c` | Add review comment on current line (Normal) or selected text (Visual) |
| `<leader>rq` | Add Claude Code Q/A item (prompt snapshot) |
| `<leader>rp` | Add general model prompt / instruction |
| `<leader>rd` | Delete anchor at current cursor position |
| `<leader>re` | Edit comment on current anchor |
| `<leader>rx` | Toggle checkbox `[ ]` $\leftrightarrow$ `[x]` |
| `<leader>rg` | Toggle `git log --graph --all` split below |
| `<leader>rP` | Preview formatted Git Commit message and Git Notes |
| `<leader>ry` | Copy Git Commit message to system clipboard |
| `<leader>rn` | Copy Git Notes payload to system clipboard |
| `<leader>rC` | Execute Git Commit and attach Git Notes |
| `<leader>rm` | Change model name (default: `gemini 3.8 flash high`) |
| `<leader>rt` | Toggle commit mode (`detailed` vs `model_only`) |

---

## Verification Plan

### Automated Tests
- Execute the Lua test runner:
  ```bash
  ./review-anchor/tests/run_tests.sh
  ```
- Verify:
  - Enclosing heading and context hunk extraction match `diff -p` expectations.
  - Commit message format adheres to model input snapshot with `[Ref N]` references and RFC 822 trailers.
  - Git Notes formatting matches `refs/notes/commits` structure.
  - Anchor lifecycle and extmarks render cleanly in headless Neovim buffers.

### Manual Verification
1. Run `./review implementation_plan.md`:
   - Verify target document opens in the top normal buffer.
   - Verify `git log --graph --all` opens in the bottom split with colored commit graph.
   - Verify cursor focus remains in top document buffer.
2. Test Org-Mode Outlining:
   - Press `<Tab>` on headings to expand/collapse subtrees.
   - Press `<S-Tab>` to cycle document-wide folding.
   - Jump between headings with `]]` and `[[`.
3. Test Review Anchoring:
   - Line anchor: press `<leader>rc` or `c`, write comment in floating window, save. Verify `[Ref 1]` badge appears.
   - Visual range anchor: select text in visual mode (`v`), press `<leader>rc`, verify anchor binds to exact snippet.
   - Claude Q/A: press `<leader>rq`, enter question and answer, verify added to session state.
4. Test Commit & Git Notes:
   - Press `<leader>rP` to inspect preview window.
   - Press `<leader>ry` and check `pbpaste` contains formatted commit message.
   - Press `<leader>rn` and check `pbpaste` contains Git Notes payload.
