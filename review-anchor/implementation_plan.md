# Git-Notes Anchors with `diff -p` Context & Claude Code Q/A Commit Integration

Architectural redesign of `review-anchor` to establish a clean separation of concerns between Git commit messages and Git Notes:
1. **Commit Message as Snapshot of Model Input**: Review comments, instructions, prompts, and Claude Code Q/A pairs are historical snapshots of contextual instructions given to the model. They are recorded in the commit message body (with reference identifiers like `[Ref 1]`), preserving immutable history without creating redundant markdown files or treating prompts like DB migrations.
2. **Git Notes for Rebase-Tolerant `diff -p` Context Anchors**: Line anchors and document positions can shift during rebases or operational transformations (OT). Git Notes attach reference numbers (`[Ref 1]`, `[Ref 2]`) to their `diff -p` type context (file path, `@@ ## Section / Context @@`, surrounding code/markdown hunks), enabling anchors to be updated or resolved across rebases without altering commit SHAs or baking stale line numbers into commit messages.
3. **Claude Code Q/A Format Interface**: Support structured Q/A interactions (questions, answers, clarifications) alongside design doc comments, treating Q/A as contextual prompt instructions rather than document annotations.
4. **Backwards Compatibility**: Retain 100% compatibility with existing repository commit messages (e.g. subject line as the model name `gemini 3.8 flash high` / `claude-3-5...`, body as prompt/context, and model-name-only temporary commits matching `pending-push`).

---

## User Review Required

> [!IMPORTANT]
> **Commit Message vs. Git Notes Division of Responsibility**:
> - **Commit Message Body**: Holds the prompt / Q&A / review comments (the contextual model input). Each comment or anchored Q&A is tagged with `[Ref N]`. No raw line numbers are hardcoded in the commit message.
> - **Git Notes (`refs/notes/commits`)**: Attaches each `[Ref N]` to its `diff -p` context (`@@ ## Hunk/Heading Context @@`, line number at commit time, snippet text). If rebased or transformed, Git Notes can be updated independently.

> [!NOTE]
> **Claude Code Format Compatibility**:
> Claude Code interacts via interactive Q/A dialogues rather than design docs. Claude previously suggested a markdown file per commit message; this plan adopts your direction: Q/A items are contextual instructions (prompts) that go directly into the commit message body, with optional `[Ref N]` diff context in Git Notes. No throwaway markdown files are created.

---

## Proposed Architecture

```
+-------------------------------------------------------------------------------+
|                                 Git Commit                                    |
|                                                                               |
|  Subject: <model_name> (e.g., gemini 3.8 flash high, claude 3.5 sonnet)       |
|  Body:                                                                        |
|    <General Prompt / Instruction>                                             |
|                                                                               |
|    [Ref 1] Review Comment / Contextual Instruction:                           |
|    Ensure 60mm diagonal corner lines match physical printer margins.          |
|                                                                               |
|    [Ref 2] Q/A Context (Claude Code):                                         |
|    Q: How should error correction handle camera tilt exceeding 45°?           |
|    A: Reject frame with haptic guidance to re-orient.                         |
+---------------------------------------+---------------------------------------+
                                        | Linked via [Ref N]
                                        v
+-------------------------------------------------------------------------------+
|                       Git Notes (refs/notes/commits)                          |
|                     (Rebase / OT Tolerant diff -p Context)                    |
|                                                                               |
|  [Ref 1] implementation_plan.md                                               |
|  Context: @@ ## User Review Required @@                                       |
|  Line: 16                                                                     |
|  Hunk:                                                                        |
|    > [!IMPORTANT]                                                             |
|    > The corner lines must be 60mm long.                                      |
|                                                                               |
|  [Ref 2] Sources/TargetCore/Geometry/CornerLineTracer.swift                   |
|  Context: @@ func computePoseRefinement() @@                                  |
|  Line: 105                                                                    |
+-------------------------------------------------------------------------------+
```

---

## Proposed Changes

### Component 1: Anchoring Engine & Data Models (`review-anchor/tui/`)

#### [MODIFY] [git_anchoring.py](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/tui/git_anchoring.py)
- **Data Models**:
  - Update `ReviewComment` with `ref_id: int` (e.g. 1, 2...), `diff_context: str` (`diff -p` header, e.g. `@@ ## Heading @@` or function signature), and `context_snippet: str` (surrounding lines / hunk).
  - Add `QAItem`: dataclass for Claude Code Q&A pairs (`ref_id: Optional[int]`, `question: str`, `answer: str`, `section_name: str`, `diff_context: str`).
- **`format_commit_message()`**:
  - Format commit message body with:
    1. General prompt / instructions.
    2. Review comments tagged with `[Ref <id>]`.
    3. Q/A items tagged with `[Ref <id>]` or formatted as conversational prompt context.
    4. Model name subject line (strictly backwards compatible with existing commits).
    5. In `model_only` mode (pending-push bookmark style), keeps subject as `<model_name>` only.
- **`format_git_notes()`**:
  - Generates structured Git Notes mapping each `[Ref <id>]` to its `diff -p` context:
    - Target file path
    - `diff -p` context (`@@ ... @@`)
    - Snippet / hunk content
    - Commit-time line number
- **Commit & Notes Execution**:
  - Update `execute_commit()` to write the commit with the model input snapshot and immediately run `git notes add -f -m "<notes>" HEAD`.
  - Add helper `resolve_diff_p_context(target_file, line_num)` to automatically extract enclosing heading/function context for any given line, simulating `diff -p`.
- **Rebase & OT Resilience**:
  - Add `update_notes_for_rebase(old_commit, new_commit)` helper that inspects `diff -p` context in Git Notes and relocates references if lines shifted during rebase.

---

### Component 2: TUI Interface (`review-anchor/tui/`)

#### [MODIFY] [wysiwyg_renderer.py](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/tui/wysiwyg_renderer.py)
- Render reference badges (e.g. `[1]`, `[2]`) in the gutter alongside line numbers when an anchor is attached.
- Render `diff -p` context hints.

#### [MODIFY] [app.py](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/tui/app.py)
- Update comment addition to assign reference numbers (`Ref 1`, `Ref 2`...).
- Add support for adding Claude Code Q&A items (keybinding `a` for Q&A prompt input).
- Update the right-hand split pane:
  - Upper section: Formatted Commit Message (Snapshot of model input, prompt, Q&A, and `[Ref N]` comments).
  - Lower section: Git Notes preview (`[Ref N]` mapped to `diff -p` context).

---

### Component 3: Web GUI Server & Frontend (`review-anchor/server.py` & `review-anchor/web/`)

#### [MODIFY] [server.py](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/server.py)
- Update `/api/plan` and `/api/comments` to return Ref IDs, `diff -p` context, and Q/A items.
- Add `/api/qa` endpoint to add/edit/delete Claude Code Q&A entries.
- Return Git Notes preview in API responses.

#### [MODIFY] [index.html](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/web/index.html)
- Add Q&A input section in the sidebar for Claude Code Q&A prompt interactions.
- Add a Git Notes preview tab/card showing how `[Ref N]` anchors attach to `diff -p` context.

#### [MODIFY] [app.js](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/web/app.js)
- Wire Q&A inputs into the live commit message builder and notes generator.
- Update `updateCommitPreview()` to render the clean commit message body (model input snapshot with `[Ref N]`) and the Git Notes payload (`diff -p` context).

---

### Component 4: Test Suite & Documentation

#### [MODIFY] [test_review_anchor.py](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/tests/test_review_anchor.py)
- Test `[Ref N]` commit message formatting with review comments and Claude Q&A.
- Test `format_git_notes()` output with `diff -p` hunk/heading headers.
- Test backwards compatibility with existing repository commit messages.
- Test Git Notes attachment via `execute_commit()`.

#### [MODIFY] [README.md](file:///Users/kds/Documents/antigravity/silly-eco/review-anchor/README.md)
- Document the new architecture: commit message as model input snapshot, Git Notes as rebase-tolerant `diff -p` anchor storage, and Claude Code Q/A integration.

---

## Verification Plan

### Automated Tests
- Run Python unittest suite:
  ```bash
  python3 -m unittest discover -s review-anchor/tests -p "test_*.py"
  ```
- Verify:
  - Commit message format matches model input snapshot with `[Ref N]`.
  - Git Notes contain accurate `diff -p` heading and hunk context.
  - Claude Q&A items render properly in commit body.
  - Backwards compatibility with model-only mode and existing commit messages.

### Manual & Interactive Verification
- Test TUI (`./review implementation_plan.md`):
  - Add comment to a line: verify `[Ref 1]` is generated.
  - Inspect commit preview (model input snapshot) and Git Notes preview (`diff -p` context).
  - Test copying commit message (`y`).
- Test Web GUI (`./review --gui`):
  - Add a line comment and a Claude Code Q&A entry.
  - Verify live commit preview updates with `[Ref 1]` and Q&A blocks.
  - Verify Git Notes tab shows the `diff -p` context.
