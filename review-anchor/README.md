# Review Anchor

A WYSIWYG review comment anchoring tool, Git Notes `diff -p` anchor manager, and git commit generator built for the `silly-eco` monorepo.

Review Anchor enables seamless pair-review between human reviewers and AI models (Antigravity IDE Gemini & Claude Code), maintaining a principled separation of concerns between commit messages and Git Notes:
- **Commit Message as Historical Model Input Snapshot**: Review comments, instructions, prompts, and Claude Code Q/A pairs are historical snapshots of contextual instructions given to the model. They belong in the commit message body under the model header (tagged with reference identifiers like `[Ref 1]`, `[Ref 2]`), keeping historical records immutable without generating throwaway markdown files per commit.
- **Git Notes for Rebase-Tolerant `diff -p` Context Anchors**: Line anchors and document locations shift when rebases or operational transformations (OT) occur. Git Notes attach each reference number (`[Ref 1]`, `[Ref 2]`) to its `diff -p` type context (`@@ ## Enclosing Heading / Symbol @@`, line number, and context hunk), enabling anchors to be tracked and updated independently of immutable commit SHAs.
- **Claude Code Q/A Format**: First-class support for conversational Q/A prompts (`Q: ... / A: ...`), treating Q/A as contextual instructions rather than document annotations.
- **Reference Bookmark (`pending-push`)**: Displays `pending-push` (`2cb59ca`) as an immutable reference bookmark preserving the example of a temporary commit format on `staging`.

---

## Features

- **Backwards-Compatible Commit Modes**:
  - **Temporary Commit (Model Name Only)**: The commit message is literally just `<model_name>` (e.g. `gemini 3.8 flash high`), matching the `pending-push` bookmark on `staging`. Review anchors attach to Git Notes.
  - **Detailed Mode (Model Input Snapshot)**: Subject line is the model name. Body contains general prompt notes, Claude Code Q/A items, line comments tagged with `[Ref N]`, and RFC 822 trailers (`Review-Doc`, `Review-Anchor`, `Reviewed-By`, `Reviewed-At`).
- **Rebase-Tolerant `diff -p` Git Notes**:
  - Automatically extracts `diff -p` hunk headers (`@@ ## Section @@` or function/class definitions) and surrounding hunk lines.
  - Stored in Git Notes (`refs/notes/commits`), keeping commit messages clean and immutable.
- **Claude Code Q/A Integration**:
  - Add and anchor interactive Q/A dialogues directly into the commit model input snapshot.
- **WYSIWYG Markdown Rendering**:
  - Line numbers gutter (`001`, `002`...) with dynamic `[★ Ref N]` badges.
  - Rendered GitHub alert callouts (`[!NOTE]`, `[!IMPORTANT]`, `[!TIP]`, `[!WARNING]`, `[!CAUTION]`).
  - Headings, code blocks, and lists styled to match Antigravity IDE.
- **Side-by-Side Matching & Font Scaling**:
  - **Terminal TUI**: Use `+` and `-` keys to adjust column wrap width dynamically to match IDE line breaks.
  - **Web GUI**: Live Font Size slider (10px–22px) and font family selector to align text side-by-side with IDE panes.
- **Copy / Paste Workflow**:
  - macOS clipboard integration (`pbcopy` and `pbpaste`).
  - One-click copy of the formatted commit message or Git Notes payload.
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
| `a` | Add Claude Code Q/A item (prompt snapshot) |
| `c` / `Enter` | Add or edit comment for selected line (assigns `[Ref N]`) |
| `d` / `x` | Delete comment on selected line |
| `p` | Paste from clipboard & jump to matching text in document |
| `m` | Configure model name (e.g. `gemini 3.8 flash high`, `claude-3-5-sonnet`) |
| `t` | Toggle commit mode (`model_only` vs `detailed`) |
| `+` / `-` | Adjust column wrap width (match IDE line breaks) |
| `Tab` / `s` | Toggle side-by-side split pane |
| `y` | Copy formatted git commit message to macOS clipboard |
| `n` | Copy Git Notes (`diff -p` context anchors) to macOS clipboard |
| `G` | Create git commit & automatically attach Git Notes |
| `?` | Show help modal |
| `q` / `Esc` | Quit |

---

### 2. Side-by-Side Web GUI Mode
Run with the `--gui` flag:
```bash
./review --gui
```
This starts a lightweight local server at `http://127.0.0.1:8765` and opens your browser.
- **Branch & Bookmark Badges**: View current branch, default branch (`staging`), and `pending-push` reference bookmark hash.
- **Claude Code Q/A Card**: Add question and answer prompt pairs with live preview.
- **Dual Preview Panels**:
  - **Commit Message Box**: Model input snapshot (prompt + Q/A + `[Ref N]` review comments).
  - **Git Notes Box**: `diff -p` context anchors mapped to each reference ID.
- **Actions**: Click **Create Commit**, **Copy Commit**, or **Copy Notes** directly from the UI.

---

## Commit & Git Notes Format Examples

### 1. Git Commit Message (Snapshot of Model Input)
```text
gemini 3.8 flash high

Approved plan with operational transformation updates.

Claude Code Q/A Context:
[Ref 1] (User Review Required)
Q: How should error correction handle camera tilt exceeding 45°?
A: Reject frame with haptic guidance to re-orient.

Reviewed implementation_plan.md:

[Ref 2] Review on "User Review Required":
> "> The corner lines must be 60mm long."
Review: Approved. Ensure 60mm is verified with physical ruler.

Review-Doc: implementation_plan.md
Review-Anchor: #user-review-required
Reviewed-By: Kent Slaney <kent@slaney.org>
Reviewed-At: 2026-09-03T12:25:21-07:00
```

### 2. Git Notes (`refs/notes/commits` - Rebase-Tolerant `diff -p` Anchors)
```text
Review Anchors (diff -p context):

[Ref 1] implementation_plan.md (Claude Q/A)
Context: @@ ## User Review Required @@
Hunk:
  > [!IMPORTANT]
  > The corner lines must be 60mm long.

[Ref 2] implementation_plan.md:L5
Context: @@ ## User Review Required @@
Hunk:
  > [!IMPORTANT]
  > The corner lines must be 60mm long.
```

---

## Running Tests
Run the unit test suite:
```bash
python3 -m unittest discover -s review-anchor/tests -p "test_*.py"
```
