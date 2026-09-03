// Review Anchor Web GUI Client Logic

let documentLines = [];
let reviewComments = [];
let qaItems = [];
let activeLineForComment = null;
let currentPlanFilename = "implementation_plan.md";
let activeCommitMode = "detailed";

// DOM Elements
const docContent = document.getElementById("docContent");
const docViewport = document.getElementById("docViewport");
const lineCountLabel = document.getElementById("lineCountLabel");
const planFilename = document.getElementById("planFilename");
const gitBranchBadge = document.getElementById("gitBranchBadge");
const pendingTagBadge = document.getElementById("pendingTagBadge");
const fontSizeSlider = document.getElementById("fontSizeSlider");
const fontSizeVal = document.getElementById("fontSizeVal");
const fontSelect = document.getElementById("fontSelect");
const searchInput = document.getElementById("searchInput");
const searchBtn = document.getElementById("searchBtn");
const commitSubject = document.getElementById("commitSubject");
const generalPrompt = document.getElementById("generalPrompt");
const commentsList = document.getElementById("commentsList");
const commentCount = document.getElementById("commentCount");
const commitPreviewBox = document.getElementById("commitPreviewBox");
const notesPreviewBox = document.getElementById("notesPreviewBox");
const copyCommitBtn = document.getElementById("copyCommitBtn");
const copyPreviewBtn = document.getElementById("copyPreviewBtn");
const copyNotesBtn = document.getElementById("copyNotesBtn");
const commitBtn = document.getElementById("commitBtn");
const clearCommentsBtn = document.getElementById("clearCommentsBtn");

// Claude Code Q/A DOM
const qaCount = document.getElementById("qaCount");
const qaQuestion = document.getElementById("qaQuestion");
const qaAnswer = document.getElementById("qaAnswer");
const addQaBtn = document.getElementById("addQaBtn");
const clearQaBtn = document.getElementById("clearQaBtn");
const qaList = document.getElementById("qaList");

// Mode radios
const modeModelOnly = document.getElementById("modeModelOnly");
const modeDetailed = document.getElementById("modeDetailed");
const modeExplanation = document.getElementById("modeExplanation");
const promptGroup = document.getElementById("promptGroup");

// Modal Elements
const commentDialog = document.getElementById("commentDialog");
const modalTitle = document.getElementById("modalTitle");
const modalSnippet = document.getElementById("modalSnippet");
const modalCommentInput = document.getElementById("modalCommentInput");
const modalCancelBtn = document.getElementById("modalCancelBtn");
const modalSaveBtn = document.getElementById("modalSaveBtn");

// Initialize
async function init() {
  setupEventListeners();
  await loadData();
}

function setupEventListeners() {
  // Font Size Slider
  fontSizeSlider.addEventListener("input", (e) => {
    const size = e.target.value + "px";
    fontSizeVal.textContent = size;
    document.documentElement.style.setProperty("--doc-font-size", size);
  });

  // Font Family Select
  fontSelect.addEventListener("change", (e) => {
    document.documentElement.style.setProperty("--doc-font-family", e.target.value);
  });

  // Mode Radios
  modeModelOnly.addEventListener("change", () => setCommitMode("model_only"));
  modeDetailed.addEventListener("change", () => setCommitMode("detailed"));

  // Preset Chips
  document.querySelectorAll(".chip").forEach(chip => {
    chip.addEventListener("click", () => {
      commitSubject.value = chip.dataset.model;
      syncConfig();
      updateCommitPreview();
    });
  });

  // Search & Jump
  searchBtn.addEventListener("click", handleSearch);
  searchInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") handleSearch();
  });

  // Commit text inputs
  commitSubject.addEventListener("input", () => {
    syncConfig();
    updateCommitPreview();
  });
  generalPrompt.addEventListener("input", updateCommitPreview);

  // Claude Code Q/A Events
  addQaBtn.addEventListener("click", handleAddQa);
  clearQaBtn.addEventListener("click", handleClearQa);

  // Copy Buttons
  copyCommitBtn.addEventListener("click", copyCommitMessage);
  copyPreviewBtn.addEventListener("click", copyCommitMessage);
  copyNotesBtn.addEventListener("click", copyNotesMessage);

  // Git Action
  commitBtn.addEventListener("click", handleCommit);

  // Clear Comments
  clearCommentsBtn.addEventListener("click", async () => {
    if (confirm("Clear all review comments?")) {
      reviewComments = [];
      await syncComments();
      renderDocument();
      renderComments();
      updateCommitPreview();
    }
  });

  // Modal Actions
  modalCancelBtn.addEventListener("click", () => commentDialog.close());
  modalSaveBtn.addEventListener("click", handleSaveComment);
}

function setCommitMode(mode) {
  activeCommitMode = mode;
  if (mode === "model_only") {
    modeModelOnly.checked = true;
    modeExplanation.textContent = "Commit message will be strictly the model name (as in pending-push). Review anchors attach to Git Notes.";
  } else {
    modeDetailed.checked = true;
    modeExplanation.textContent = "Commit message includes snapshot of model input (prompt, Q/A, [Ref N] comments). Git Notes store diff -p anchors.";
  }
  syncConfig();
  updateCommitPreview();
}

async function loadData() {
  try {
    const res = await fetch("/api/plan");
    const data = await res.json();
    documentLines = data.lines || [];
    qaItems = data.qa_items || [];
    currentPlanFilename = data.filename || "implementation_plan.md";
    planFilename.textContent = currentPlanFilename;
    lineCountLabel.textContent = `${documentLines.length} lines`;

    if (data.model_header) {
      commitSubject.value = data.model_header;
    }

    if (data.commit_mode) {
      setCommitMode(data.commit_mode);
    }

    // Update Git Status Badges
    const branchText = `${data.branch || 'unknown'} → ${data.default_branch || 'staging'}`;
    gitBranchBadge.textContent = branchText;

    if (data.pending_push_hash) {
      pendingTagBadge.textContent = `Bookmark: pending-push (${data.pending_push_hash})`;
    } else {
      pendingTagBadge.textContent = "Bookmark: pending-push";
    }

    const commRes = await fetch("/api/comments");
    reviewComments = await commRes.json();

    renderDocument();
    renderComments();
    renderQa();
    await updateCommitPreview();
  } catch (err) {
    console.error("Failed to load plan data:", err);
  }
}

async function syncConfig() {
  try {
    await fetch("/api/config", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model_name: commitSubject.value.trim(),
        commit_mode: activeCommitMode
      })
    });
  } catch (err) {
    console.error("Failed to sync config:", err);
  }
}

function renderDocument() {
  docContent.innerHTML = "";
  const commentMap = new Map();
  reviewComments.forEach(c => {
    commentMap.set(c.line_number, c);
  });

  documentLines.forEach((item, idx) => {
    const lineEl = document.createElement("div");
    lineEl.className = "doc-line";
    lineEl.dataset.lineNum = item.line_number;
    lineEl.dataset.idx = idx;

    const existingComment = commentMap.get(item.line_number);
    if (existingComment) {
      lineEl.classList.add("has-comment");
    }

    const gutter = document.createElement("div");
    gutter.className = "line-gutter";
    gutter.textContent = String(item.line_number).padStart(3, "0");

    const content = document.createElement("div");
    content.className = "line-content";

    if (item.line_type === "heading") {
      const hClass = item.heading_level === 1 ? "md-h1" : (item.heading_level === 2 ? "md-h2" : "md-h3");
      content.classList.add("md-heading", hClass);
      content.textContent = item.raw_text;
    } else if (item.line_type === "alert") {
      content.classList.add("md-alert", `alert-${(item.alert_type || 'note').toLowerCase()}`);
      content.innerHTML = `<strong>[!${item.alert_type}]</strong> ${escapeHtml(item.alert_body || item.raw_text)}`;
    } else if (item.line_type === "code_fence" || item.line_type === "code_body") {
      content.classList.add("md-code");
      content.textContent = item.raw_text;
    } else if (item.line_type === "horizontal_rule") {
      content.classList.add("md-hr");
    } else if (item.line_type === "blank") {
      content.classList.add("md-blank");
      content.innerHTML = "&nbsp;";
    } else {
      content.textContent = item.raw_text;
    }

    if (existingComment) {
      const badge = document.createElement("span");
      badge.className = "badge-comment";
      badge.textContent = `★ Ref ${existingComment.ref_id || '1'}`;
      content.appendChild(badge);
    }

    lineEl.appendChild(gutter);
    lineEl.appendChild(content);

    lineEl.addEventListener("click", () => openCommentModal(item));

    docContent.appendChild(lineEl);
  });
}

function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

function openCommentModal(lineItem) {
  activeLineForComment = lineItem;
  modalTitle.textContent = `Anchor Review Comment - Line ${lineItem.line_number}`;
  modalSnippet.textContent = lineItem.raw_text.trim() || "(blank line)";

  const existing = reviewComments.find(c => c.line_number === lineItem.line_number);
  modalCommentInput.value = existing ? existing.comment_text : "";

  commentDialog.showModal();
  modalCommentInput.focus();
}

async function handleSaveComment() {
  const commentText = modalCommentInput.value.trim();
  if (!commentText || !activeLineForComment) {
    commentDialog.close();
    return;
  }

  let secName = "";
  let secSlug = "";
  const curIdx = parseInt(activeLineForComment.line_number, 10);
  for (let i = curIdx - 1; i >= 0; i--) {
    if (documentLines[i] && documentLines[i].line_type === "heading") {
      secName = documentLines[i].raw_text.replace(/^#+\s*/, "").trim();
      secSlug = documentLines[i].heading_slug || "";
      break;
    }
  }

  const existingIdx = reviewComments.findIndex(c => c.line_number === activeLineForComment.line_number);
  if (existingIdx >= 0) {
    reviewComments[existingIdx].comment_text = commentText;
  } else {
    reviewComments.push({
      line_number: activeLineForComment.line_number,
      line_text: activeLineForComment.raw_text,
      section_name: secName,
      section_slug: secSlug,
      comment_text: commentText,
      timestamp: new Date().toISOString()
    });
  }

  await syncComments();
  await loadData();
  commentDialog.close();
}

async function syncComments() {
  try {
    await fetch("/api/comments", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(reviewComments)
    });
  } catch (err) {
    console.error("Failed to sync comments:", err);
  }
}

function renderComments() {
  commentCount.textContent = reviewComments.length;
  commentsList.innerHTML = "";

  if (reviewComments.length === 0) {
    commentsList.innerHTML = `<div class="empty-state">Click any line in the document to anchor a review comment.</div>`;
    return;
  }

  reviewComments.forEach((c, idx) => {
    const card = document.createElement("div");
    card.className = "comment-card";

    const header = document.createElement("div");
    header.className = "comment-card-header";
    const refTag = c.ref_id ? `<span class="ref-badge">Ref ${c.ref_id}</span> ` : "";
    header.innerHTML = `<span>${refTag}Line ${c.line_number} ${c.section_name ? `(${c.section_name})` : ''}</span>`;

    const delBtn = document.createElement("button");
    delBtn.className = "delete-comment-btn";
    delBtn.textContent = "✕";
    delBtn.title = "Delete comment";
    delBtn.addEventListener("click", async (e) => {
      e.stopPropagation();
      reviewComments.splice(idx, 1);
      await syncComments();
      await loadData();
    });
    header.appendChild(delBtn);

    const snippet = document.createElement("div");
    snippet.className = "comment-card-snippet";
    snippet.textContent = `> ${c.line_text}`;

    const text = document.createElement("div");
    text.className = "comment-card-text";
    text.textContent = c.comment_text;

    card.appendChild(header);
    if (c.line_text) card.appendChild(snippet);
    card.appendChild(text);

    card.addEventListener("click", () => {
      const lineEl = docContent.querySelector(`[data-line-num="${c.line_number}"]`);
      if (lineEl) {
        lineEl.scrollIntoView({ behavior: "smooth", block: "center" });
        lineEl.classList.add("highlight-match");
        setTimeout(() => lineEl.classList.remove("highlight-match"), 1800);
      }
    });

    commentsList.appendChild(card);
  });
}

// Claude Code Q/A logic
async function handleAddQa() {
  const q = qaQuestion.value.trim();
  const a = qaAnswer.value.trim();
  if (!q && !a) return;

  try {
    await fetch("/api/qa", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ question: q, answer: a })
    });
    qaQuestion.value = "";
    qaAnswer.value = "";
    await loadData();
  } catch (err) {
    alert("Failed to add Q/A: " + err);
  }
}

async function handleClearQa() {
  if (!confirm("Clear all Claude Code Q/A items?")) return;
  try {
    await fetch("/api/qa", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "clear" })
    });
    await loadData();
  } catch (err) {
    alert("Failed to clear Q/A: " + err);
  }
}

function renderQa() {
  qaCount.textContent = qaItems.length;
  qaList.innerHTML = "";

  if (qaItems.length === 0) {
    qaList.innerHTML = `<div class="empty-state">No Q/A items added yet.</div>`;
    return;
  }

  qaItems.forEach((q, idx) => {
    const card = document.createElement("div");
    card.className = "qa-card";

    const header = document.createElement("div");
    header.className = "qa-card-header";
    const refTag = q.ref_id ? `<span class="ref-badge">Ref ${q.ref_id}</span> ` : "";
    header.innerHTML = `<span>${refTag}${q.section_name ? `(${q.section_name})` : 'Contextual Instruction'}</span>`;

    const delBtn = document.createElement("button");
    delBtn.className = "delete-comment-btn";
    delBtn.textContent = "✕";
    delBtn.title = "Delete Q/A";
    delBtn.addEventListener("click", async () => {
      await fetch("/api/qa", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "delete", index: idx })
      });
      await loadData();
    });
    header.appendChild(delBtn);

    const qEl = document.createElement("div");
    qEl.className = "qa-q";
    qEl.textContent = `Q: ${q.question}`;

    const aEl = document.createElement("div");
    aEl.className = "qa-a";
    aEl.textContent = `A: ${q.answer}`;

    card.appendChild(header);
    card.appendChild(qEl);
    card.appendChild(aEl);
    qaList.appendChild(card);
  });
}

async function updateCommitPreview() {
  const prompt = generalPrompt.value.trim();
  try {
    const res = await fetch("/api/preview", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        prompt: prompt,
        mode: activeCommitMode
      })
    });
    if (res.ok) {
      const data = await res.json();
      commitPreviewBox.textContent = data.commit_message || "";
      notesPreviewBox.textContent = data.git_notes || "(No Git Notes anchors attached)";
    }
  } catch (err) {
    console.error("Failed to update commit preview:", err);
  }
}

function handleSearch() {
  const query = searchInput.value.trim().toLowerCase();
  if (!query) return;

  docContent.querySelectorAll(".highlight-match").forEach(el => el.classList.remove("highlight-match"));
  let matchedLineEl = null;

  if (/^\d+$/.test(query)) {
    matchedLineEl = docContent.querySelector(`[data-line-num="${query}"]`);
  } else {
    for (const item of documentLines) {
      if (item.raw_text.toLowerCase().includes(query)) {
        matchedLineEl = docContent.querySelector(`[data-line-num="${item.line_number}"]`);
        break;
      }
    }
  }

  if (matchedLineEl) {
    matchedLineEl.scrollIntoView({ behavior: "smooth", block: "center" });
    matchedLineEl.classList.add("highlight-match");
    setTimeout(() => matchedLineEl.classList.remove("highlight-match"), 2500);
  } else {
    alert(`No matching text found for: "${query}"`);
  }
}

async function copyCommitMessage() {
  const textToCopy = commitPreviewBox.textContent;
  try {
    await navigator.clipboard.writeText(textToCopy);
    const origText = copyCommitBtn.textContent;
    copyCommitBtn.textContent = "✓ Copied!";
    copyPreviewBtn.textContent = "✓ Copied!";
    setTimeout(() => {
      copyCommitBtn.textContent = origText;
      copyPreviewBtn.textContent = "Copy Commit";
    }, 2000);
  } catch (err) {
    alert("Could not copy to clipboard: " + err);
  }
}

async function copyNotesMessage() {
  const textToCopy = notesPreviewBox.textContent;
  try {
    await navigator.clipboard.writeText(textToCopy);
    const origText = copyNotesBtn.textContent;
    copyNotesBtn.textContent = "✓ Copied!";
    setTimeout(() => {
      copyNotesBtn.textContent = origText;
    }, 2000);
  } catch (err) {
    alert("Could not copy notes: " + err);
  }
}

async function handleCommit() {
  const modelName = commitSubject.value.trim() || "gemini 3.8 flash high";
  const modeDesc = (activeCommitMode === "model_only") ? "Temporary Commit (Model Name Only)" : "Detailed Review Commit";

  if (!confirm(`Create git commit [${modeDesc}] with message "${modelName}"?`)) return;

  try {
    const res = await fetch("/api/commit", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        mode: activeCommitMode,
        prompt: generalPrompt.value.trim()
      })
    });
    const data = await res.json();
    alert(data.message || "Commit completed!");
    await loadData();
  } catch (err) {
    alert("Commit failed: " + err);
  }
}

init();
