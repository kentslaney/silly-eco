# Implementation Plan: Inline Instructions, Git Log Fixes & Repo Onboarding

Refine `review-anchor` and the `./review` wrapper to support inline instruction splits with git rebase semantics, fix git log paging and line-wrapping artifacts, support running `./review` without a design doc (defaulting to inline instructions above the git log), and provide interactive GitHub-style repository initialization for uninitialized workspaces.

---

## User Review Required

> [!IMPORTANT]
> **Inline Instructions Split (`<leader>ri` / `<leader>i`)**:
> - Creates a buffer in a split placed **above the git log graph** if open, or **below the current window** otherwise.
> - Follows git rebase/commit semantics: quitting without saving (`:q!`, `:cq`, `ZQ`) cancels the operation; saving & quitting (`:wq`, `:x`, `ZZ`) commits the staged changes with the written instructions, attaches Git Notes, and refreshes the git log graph.
> - Opening the floating model prompt window (`<leader>rp`) pulls the current text from the inline instructions, temporarily closes the inline split, and restores the inline split with the updated prompt upon closing.

> [!IMPORTANT]
> **Default Layout & Uninitialized Repository Onboarding**:
> - If `./review` is run without an implementation plan file, the layout defaults to **just the inline instructions split above the git log graph** (no dummy `review.md`).
> - If the repo is not initialized with git, it prompts for a remote repository URL and license choice (CC0, MIT, GPL-3.0, Apache-2.0, BSD-3-Clause, None). It runs `git init`, creates the initial commit with the license, creates a blank `.gitignore`, and opens the git log and inline instructions splits with model name omitted from the first line of the first prompt commit.

---

## Proposed Changes

### 1. Fix Git Log Graph Paging & Wrapping (`...skipping...` and 80-char wrap)

#### [MODIFY] [config.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/config.lua)
- Update `git_log_cmd` to `git --no-pager log --graph --all --decorate --color=always`.
- Running with `--no-pager` prevents Git from launching `less`, eliminating `...skipping...` messages and pager line chopping.
- Add `omit_model_header = false` option to `M.defaults`.

#### [MODIFY] [splits.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/splits.lua)
- Ensure the terminal buffer runs `git --no-pager log` and terminal window options properly support smooth reading.

---

### 2. Inline Instructions Split Module

#### [NEW] [inline.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/lua/review_anchor/inline.lua)
- Create `review_anchor.inline` module:
  - `open_inline_instructions(initial_content)`:
    - Finds `splits.git_log_win`: if valid, opens split *above* git log via `aboveleft split`; otherwise opens *below* current window via `belowright split`.
    - Creates a temporary buffer with markdown syntax, soft-wrapping enabled (`wrap = true`, `linebreak = true`, `breakindent = true`).
    - Pre-populates with instructions template or existing prompt.
  - Rebase semantics via buffer autocommands:
    - Tracks whether the buffer was saved (`BufWritePost` sets `was_saved = true`).
    - On window/buffer close (`BufWinLeave`):
      - If `was_saved` is true: extracts text (filtering `#` comments), updates `anchors.set_prompt()`, and calls `git.execute_commit()` which stages all changes (`git add -A`), commits, attaches Git Notes, and refreshes the git log split below.
      - If `was_saved` is false: aborts commit and notifies user that the operation was cancelled.
    - Buffer keymaps: `:wq`, `:q!`, `<C-c><C-c>` (save & commit), `<C-c><C-k>` (cancel & quit), `<C-s>` (save).
  - Integration helpers:
    - `is_open()`: checks if the inline split window is currently open and valid.
    - `get_content_raw()`: extracts current buffer text without closing.
    - `close_split_temporary()`: closes window without triggering cancel notification.

---

### 3. Model Prompt Floating Window Coordination

#### [MODIFY] [capture.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/capture.lua)
- In `open_prompt_capture()`:
  - If `inline.is_open()` is true:
    - Pull current text from inline split via `inline.get_content_raw()`.
    - Temporarily close the inline split.
    - Open the floating window pre-filled with this content.
    - Upon closing or saving the floating window, restore the inline instructions split above the git log graph with the updated content.

---

### 4. Git Commit Generator (Support Omit Model Header for First Prompt)

#### [MODIFY] [git.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/git.lua)
- In `format_commit_message()`:
  - If `config.options.omit_model_header` is true:
    - Do NOT prepend `model` or empty line to the commit message.
    - Emit the prompt directly as the commit subject/body.
    - Reset `config.options.omit_model_header = false` once formatted/committed.

---

### 5. License Templates & Uninitialized Repo Onboarding

#### [NEW] [license.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/license.lua)
- Provide license generation templates for:
  - `CC0 1.0 Universal`
  - `MIT License`
  - `GNU General Public License v3.0 (GPL)`
  - `Apache License 2.0`
  - `BSD 3-Clause License`
  - `Unlicense`
- Functions to write `LICENSE` with current year and author name from git config.

#### [MODIFY] [review](file:///Users/kds/Documents/antigravity/silly-eco/review)
- Check if inside a git working tree via `git rev-parse --is-inside-work-tree`:
  - If NOT initialized:
    - Prompt user for remote repository URL (optional).
    - Prompt user to select a license (CC0, MIT, GPL, Apache, BSD, None) matching GitHub.
    - Initialize git repo (`git init -b main`).
    - If remote provided, run `git remote add origin <url>`.
    - Write selected `LICENSE` and create initial commit (`Initial commit`).
    - Create blank `.gitignore` (`touch .gitignore`) and stage it (`git add .gitignore`).
    - Launch Neovim with `first_prompt_no_model = true`.
- If no file argument is passed ($# == 0), pass empty target so Neovim opens only the inline instruction split above the git log.

#### [MODIFY] [init.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/lua/review_anchor/init.lua)
- Add keybinding:
  - `<leader>ri` and `<leader>i`: open inline instructions split.
- Update `M.start(filepath, opts)`:
  - If `opts.first_prompt_no_model` is true, set `config.options.omit_model_header = true`.
  - If no `filepath` provided:
    - Open git log split below.
    - Open inline instruction split above git log.
    - Do NOT open dummy buffer.
  - If `filepath` provided:
    - Open `filepath` in upper window, attach review layer, open git log below.
- Add Lua fallback for `M.init_repo(opts)` if called within an uninitialized repo from Lua.

---

### 6. Documentation & Test Suite

#### [MODIFY] [README.md](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/README.md)
- Document `<leader>ri` / `<leader>i` keybinding and rebase-like `:wq`/`:q!` workflow.
- Document no-plan startup layout and uninitialized repository onboarding.

#### [MODIFY] [tests/test_git_notes.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/tests/test_git_notes.lua) & [tests/test_startup.lua](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/tests/test_startup.lua)
- Add tests for:
  - `git --no-pager` in `git_log_cmd`.
  - `omit_model_header` behavior for first prompt commit.
  - Inline instructions buffer creation, save-commit, and cancel-abort.
  - Integration between inline split and floating prompt capture.
  - Repo initialization and license generation.

---

## Verification Plan

### Automated Tests
Run via headless test suite:
```bash
./review-anchor/tests/run_tests.sh
```
1. `test_diff_p.lua`: verify diff -p context parsing remains intact.
2. `test_git_notes.lua`: verify commit message formatting with and without model header (`omit_model_header`), `[blank]` toggle, and staging.
3. `test_startup.lua`: verify startup with no file provided opens inline instructions split above git log split, soft-wrap is enabled, and git log command uses `--no-pager`.
4. `test_inline.lua` (new): verify inline split positioning (above git log), rebase save (:wq) vs abort (:q!), and floating window text transfer.
5. `test_repo_init.lua` (new): verify uninitialized repo setup, license creation, blank `.gitignore` staging, and initial commit creation.

### Manual Verification
- Run `./review` in an uninitialized temp directory to verify remote URL / license prompts, `.gitignore` creation, initial commit, and first prompt commit without model name.
- Run `./review` with no argument in the monorepo: verify layout consists of inline instructions split above git log graph.
- Test `:wq` to commit and `:q!` to cancel.
- Press `<leader>rp` while in inline split: verify text transfers to floating window, inline split temporarily closes, and re-opens updated upon closing.
