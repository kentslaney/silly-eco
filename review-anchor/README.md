# Review Anchor

A WYSIWYG review comment anchoring tool and git commit generator built for the `silly-eco` monorepo.

Review Anchor allows you to inspect implementation plans side-by-side with the Antigravity IDE, anchor comments to specific lines and sections, and generate git commit messages that match your repository's workflow:
- **`pending-push` Tag & Staging Branch Integration**: Tracks `refs/heads/staging` (GitHub default branch) and the `pending-push` tag.
- **Model Name Only Mode**: Commit message is strictly the (configurable) model name (e.g. `gemini 3.8 flash high`), with review comments preserved in Git Notes.
- **Detailed Mode**: Full commit body containing the review prompt, line quotes, section anchors, and RFC 822 trailers.

---

## Features

- **Backwards-Compatible Commit Modes**:
  - **Model Name Only (pending-push style)**: The commit message is literally just `<model_name>` (e.g. `gemini 3.8 flash high`). Line comments and metadata are recorded to Git Notes (`git notes add`) for posterity, keeping the git log clean.
  - **Detailed Mode**: Subject line is the model name, followed by prompt notes, line references, snippets, and trailers (`Review-Doc`, `Review-Anchor`, `Reviewed-By`, `Reviewed-At`).
- **Tag & Branch UX**:
  - Automatically identifies current branch vs default target (`staging`).
  - Displays `pending-push` tag status (commit hash and whether HEAD matches).
  - Quick action to move/create `pending-push` tag (`git tag -f pending-push HEAD`).
  - Quick action to **Commit & Tag pending-push** in one step.
- **WYSIWYG Markdown Rendering**:
  - Line numbers gutter (`001`, `002`...).
  - Rendered GitHub alert callouts (`[!NOTE]`, `[!IMPORTANT]`, `[!TIP]`, `[!WARNING]`, `[!CAUTION]`).
  - Headings, code blocks, and lists styled to match Antigravity IDE.
- **Side-by-Side Matching & Font Scaling**:
  - **Terminal TUI**: Use `+` and `-` keys to adjust column wrap width dynamically to match IDE line breaks.
  - **Web GUI**: Use the live Font Size slider (10px–22px) and font family selector to align text side-by-side with the IDE pane.
- **Copy / Paste Workflow**:
  - Direct integration with macOS clipboard (`pbcopy` and `pbpaste`).
  - Paste any snippet copied from the Antigravity IDE to immediately jump to and highlight matching lines.
  - One-click copy of the generated git commit message to paste into git or chat.
- **Zero External Dependencies**:
  - Built entirely using the Python 3 standard library (`curses`, `http.server`, `subprocess`, `json`).

---

## Quick Start

### 1. Terminal TUI Mode (Default)
Run from the monorepo root:
```bash
./review
```
Or specify a plan file explicitly:
```bash
./review path/to/implementation_plan.md
```

#### Keybindings
| Key | Action |
| --- | --- |
| `j` / `↓` | Move down 1 line |
| `k` / `↑` | Move up 1 line |
| `PgDn` / `PgUp` | Page down / Page up |
| `c` / `Enter` | Add or edit comment for selected line (or paste from clipboard) |
| `d` / `x` | Delete comment on selected line |
| `p` | Paste from clipboard & jump to matching text in document |
| `m` | Configure model name (e.g. `gemini 3.8 flash high`) |
| `t` | Toggle commit mode (`model_only` vs `detailed`) |
| `+` / `-` | Adjust column wrap width (match IDE line breaks) |
| `Tab` / `s` | Toggle side-by-side split pane |
| `y` | Copy formatted git commit message to macOS clipboard |
| `G` | Run `git commit` |
| `P` | **Commit AND tag `pending-push`** |
| `T` | Tag current HEAD as `pending-push` |
| `?` | Show help modal |
| `q` / `Esc` | Quit |

---

### 2. Side-by-Side Web GUI Mode
Run with the `--gui` flag:
```bash
./review --gui
```
This starts a lightweight local server at `http://127.0.0.1:8765` and opens your browser.
- **Branch & Tag Badges**: View current branch, default branch (`staging`), and `pending-push` tag hash in the header.
- **Format Toggle**: Choose between **Model Name Only** (as in `pending-push`) and **Detailed Review**.
- **Model Preset Chips**: Click quick chips (`gemini 3.8 flash high`, `gemini 1.5 pro`, `claude 3.5`) or type a custom name.
- **Actions**: Click **Tag pending-push**, **Commit**, or **Commit & Tag pending-push** directly from the UI.

---

## Commit Format Examples

### Mode 1: Model Name Only (Matching `pending-push`)
```text
gemini 3.8 flash high
```
*(Review anchors are attached to the commit object via Git Notes for posterity, viewable with `git log --show-notes`)*

### Mode 2: Detailed Review
```text
gemini 3.8 flash high

Approved plan. Ensure 60mm diagonal corner lines match physical printer margins.

Reviewed implementation_plan.md:

[Line 16] Section: "User Review Required"
> "> **Git Commit Message Format Compatibility**:"
Review: Verified format compatibility with git log.

Review-Doc: implementation_plan.md
Review-Anchor: #user-review-required
Reviewed-By: Kent Slaney <kent@slaney.org>
Reviewed-At: 2026-09-02T16:32:32-07:00
```

---

## Running Tests
Run the unit test suite:
```bash
python3 -m unittest discover -s review-anchor/tests -p "test_*.py"
```
