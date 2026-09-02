# Review Anchor

A WYSIWYG review comment anchoring tool and git commit generator built for the `silly-eco` monorepo.

Review Anchor allows you to inspect implementation plans side-by-side with the Antigravity IDE, anchor comments to specific lines and sections, and generate git commit messages that are **100% backwards-compatible** with your existing commit scheme.

---

## Features

- **Backwards-Compatible Commit Formatting**:
  - Automatically matches your current scheme (`gemini 3.8 flash high\n\n<review/prompt>`).
  - Appends machine-readable review anchors, line numbers, quoted snippets, and RFC 822 trailers (`Review-Doc`, `Review-Anchor`, `Reviewed-By`, `Reviewed-At`).
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
python3 review-anchor/review_anchor.py
```
Or specify a plan file explicitly:
```bash
python3 review-anchor/review_anchor.py path/to/implementation_plan.md
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
| `+` / `-` | Adjust column wrap width (match IDE font size) |
| `Tab` / `s` | Toggle side-by-side split pane |
| `y` | Copy formatted git commit message to macOS clipboard |
| `G` | Directly run `git commit -m ...` |
| `?` | Show help modal |
| `q` / `Esc` | Quit |

---

### 2. Side-by-Side Web GUI Mode
Run with the `--gui` flag:
```bash
python3 review-anchor/review_anchor.py --gui
```
This starts a lightweight local server at `http://127.0.0.1:8765` and opens your browser.
- Adjust the **Font Size Slider** to visually match Antigravity IDE line wrapping.
- Click any line in the document to open the comment dialog.
- Click **Copy Git Commit** to copy the formatted message to your clipboard.

---

## Git Commit Format Example

```text
gemini 3.8 flash high

User review feedback on implementation plan.

Reviewed implementation_plan.md:

[Line 16] Section: "User Review Required"
> "The existing commit format in this repository follows:"
Review: Approved format. Backwards compatibility verified.

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
