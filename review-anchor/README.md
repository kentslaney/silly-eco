# Review Anchor

A WYSIWYG review comment anchoring tool and git commit generator built for the `silly-eco` monorepo.

Review Anchor allows you to inspect implementation plans side-by-side with the Antigravity IDE, anchor comments to specific lines and sections, and generate git commit messages that match your repository's workflow:
- **Reference Bookmark (`pending-push`)**: Displays `pending-push` (`2cb59ca`) as an immutable reference bookmark preserving the example of a temporary commit format on `staging`.
- **Temporary Commit (Model Name Only)**: Commit message is strictly the (configurable) model name (e.g. `gemini 3.8 flash high`), exactly like the `pending-push` exemplar. Line review comments are preserved in Git Notes for posterity.
- **Detailed Mode**: Full commit body containing the review prompt, line quotes, section anchors, and RFC 822 trailers.

---

## Features

- **Backwards-Compatible Commit Modes**:
  - **Temporary Commit (Model Name Only)**: The commit message is literally just `<model_name>` (e.g. `gemini 3.8 flash high`), matching the `pending-push` bookmark on `staging`. Line comments and metadata are recorded to Git Notes (`git notes add`) for posterity, keeping the git log clean while the branch moves.
  - **Detailed Mode**: Subject line is the model name, followed by prompt notes, line references, snippets, and trailers (`Review-Doc`, `Review-Anchor`, `Reviewed-By`, `Reviewed-At`).
- **Bookmark & Branch Awareness**:
  - Displays current branch vs default target (`staging`).
  - Displays the `pending-push` reference bookmark (`2cb59ca`) without modifying or overwriting it.
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
| `G` | Create git commit |
| `?` | Show help modal |
| `q` / `Esc` | Quit |

---

### 2. Side-by-Side Web GUI Mode
Run with the `--gui` flag:
```bash
./review --gui
```
This starts a lightweight local server at `http://127.0.0.1:8765` and opens your browser.
- **Branch & Bookmark Badges**: View current branch, default branch (`staging`), and the `pending-push` reference bookmark hash in the header.
- **Format Toggle**: Choose between **Temporary Commit (Model Name Only - matching pending-push bookmark)** and **Detailed Review**.
- **Model Preset Chips**: Click quick chips (`gemini 3.8 flash high`, `gemini 1.5 pro`, `claude 3.5`) or type a custom name.
- **Actions**: Click **Create Commit** or **Copy Git Commit** directly from the UI.

---

## Commit Format Examples

### Mode 1: Temporary Commit (Matching `pending-push` Bookmark)
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
