// Review Anchor Web GUI Client Logic

let documentLines = [];
let reviewComments = [];
let activeLineForComment = null;
let currentPlanFilename = "implementation_plan.md";
let activeCommitMode = "model_only";

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
const copyCommitBtn = document.getElementById("copyCommitBtn");
const copyPreviewBtn = document.getElementById("copyPreviewBtn");
const commitBtn = document.getElementById("commitBtn");
const commitAndTagBtn = document.getElementById("commitAndTagBtn");
const tagPendingBtn = document.getElementById("tagPendingBtn");
const clearCommentsBtn = document.getElementById("clearCommentsBtn");

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

  // Copy Buttons
  copyCommitBtn.addEventListener("click", copyCommitMessage);
  copyPreviewBtn.addEventListener("click", copyCommitMessage);

  // Git Actions
  tagPendingBtn.addEventListener("click", handleTagPending);
  commitBtn.addEventListener("click", () => handleCommit(false));
  commitAndTagBtn.addEventListener("click", () => handleCommit(true));

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
    modeExplanation.textContent = "Commit message will be strictly the model name. Review anchors are attached via Git Notes.";
  } else {
    modeDetailed.checked = true;
    modeExplanation.textContent = "Commit message includes model name, user review prompt, line quotes, and RFC 822 review trailers.";
  }
  syncConfig();
  updateCommitPreview();
}

async function loadData() {
  try {
    const res = await fetch("/api/plan");
    const data = await res.json();
    documentLines = data.lines || [];
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
      pendingTagBadge.textContent = `pending-push: ${data.pending_push_hash}${data.is_at_pending_push ? ' ✓' : ''}`;
    } else {
      pendingTagBadge.textContent = "pending-push: (none)";
    }

    const commRes = await fetch("/api/comments");
    reviewComments = await commRes.json();

    renderDocument();
    renderComments();
    updateCommitPreview();
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
  const commentedLineNumbers = new Set(reviewComments.map(c => c.line_number));

  documentLines.forEach((item, idx) => {
    const lineEl = document.createElement("div");
    lineEl.className = "doc-line";
    lineEl.dataset.lineNum = item.line_number;
    lineEl.dataset.idx = idx;

    if (commentedLineNumbers.has(item.line_number)) {
      lineEl.classList.add("has-comment");
    }

    const gutter = document.createElement("div");
    gutter.className = "line-gutter";
    gutter.textContent = String(item.line_number).padStart(3, "0");

    const content = document.createElement("div");
    content.className = "line-content";

    if (item.line_type === "heading") {
      lineEl.classList.add(`line-h${item.heading_level}`);
      content.textContent = item.raw_text;
    } else if (item.line_type === "alert") {
      lineEl.classList.add("line-alert", `alert-${item.alert_type}`);
      const badge = document.createElement("span");
      badge.className = "alert-badge";
      badge.textContent = `[!${item.alert_type}]`;
      content.appendChild(badge);
      content.appendChild(document.createTextNode(" " + (item.alert_body || item.raw_text)));
    } else if (item.line_type === "code_body" || item.line_type === "code_fence") {
      content.classList.add("line-code");
      content.textContent = item.raw_text;
    } else if (item.line_type === "horizontal_rule") {
      content.classList.add("line-hr");
    } else {
      content.textContent = item.raw_text || "\u00A0";
    }

    if (commentedLineNumbers.has(item.line_number)) {
      const count = reviewComments.filter(c => c.line_number === item.line_number).length;
      const pill = document.createElement("span");
      pill.className = "line-comment-pill";
      pill.textContent = `★ ${count}`;
      content.appendChild(pill);
    }

    lineEl.appendChild(gutter);
    lineEl.appendChild(content);
    lineEl.addEventListener("click", () => openCommentModal(item));
    docContent.appendChild(lineEl);
  });
}

function openCommentModal(item) {
  activeLineForComment = item;
  modalTitle.textContent = `Anchor Comment on Line ${item.line_number}`;
  modalSnippet.textContent = item.raw_text ? `"${item.raw_text}"` : "(empty line)";
  modalCommentInput.value = "";
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
  for (let i = activeLineForComment.line_number - 1; i >= 0; i--) {
    if (documentLines[i] && documentLines[i].line_type === "heading") {
      secName = documentLines[i].raw_text.replace(/^#+\s*/, "");
      secSlug = documentLines[i].heading_slug || "section";
      break;
    }
  }

  reviewComments.push({
    line_number: activeLineForComment.line_number,
    line_text: activeLineForComment.raw_text,
    section_name: secName,
    section_slug: secSlug,
    comment_text: commentText,
    timestamp: new Date().toISOString()
  });

  await syncComments();
  renderDocument();
  renderComments();
  updateCommitPreview();
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
    header.innerHTML = `<span>Line ${c.line_number} ${c.section_name ? `(${c.section_name})` : ''}</span>`;
    
    const delBtn = document.createElement("button");
    delBtn.className = "delete-comment-btn";
    delBtn.textContent = "✕";
    delBtn.title = "Delete comment";
    delBtn.addEventListener("click", async (e) => {
      e.stopPropagation();
      reviewComments.splice(idx, 1);
      await syncComments();
      renderDocument();
      renderComments();
      updateCommitPreview();
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

function updateCommitPreview() {
  const modelName = commitSubject.value.trim() || "gemini 3.8 flash high";

  if (activeCommitMode === "model_only") {
    // Exact match to pending-push tag: JUST the configurable model name!
    let preview = modelName;
    if (reviewComments.length > 0) {
      preview += `\n\n# Note: ${reviewComments.length} review anchor(s) will be recorded to Git Notes (keeping commit message clean).`;
    }
    commitPreviewBox.textContent = preview;
    return;
  }

  // Detailed mode
  const prompt = generalPrompt.value.trim();
  let bodyBlocks = [];
  if (prompt) {
    bodyBlocks.push(prompt);
  }

  if (reviewComments.length > 0) {
    const entries = [];
    entries.push(`Reviewed ${currentPlanFilename}:`);

    reviewComments.forEach(c => {
      const secInfo = c.section_name ? ` Section: "${c.section_name}"` : "";
      const snippet = c.line_text ? `> "${c.line_text}"` : "";
      entries.push(`[Line ${c.line_number}]${secInfo}\n${snippet}\nReview: ${c.comment_text}`);
    });

    bodyBlocks.push(entries.join("\n\n"));

    const trailers = [];
    trailers.push(`Review-Doc: ${currentPlanFilename}`);
    const primarySlug = reviewComments[0].section_slug || `L${reviewComments[0].line_number}`;
    trailers.push(`Review-Anchor: #${primarySlug}`);
    trailers.push(`Reviewed-At: ${new Date().toISOString()}`);
    bodyBlocks.push(trailers.join("\n"));
  }

  const fullMsg = bodyBlocks.length > 0
    ? `${modelName}\n\n${bodyBlocks.join("\n\n")}`
    : modelName;

  commitPreviewBox.textContent = fullMsg;
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
  const modelName = commitSubject.value.trim() || "gemini 3.8 flash high";
  const textToCopy = (activeCommitMode === "model_only") ? modelName : commitPreviewBox.textContent;

  try {
    await navigator.clipboard.writeText(textToCopy);
    const origText = copyCommitBtn.textContent;
    copyCommitBtn.textContent = "✓ Copied!";
    copyPreviewBtn.textContent = "✓ Copied!";
    setTimeout(() => {
      copyCommitBtn.textContent = origText;
      copyPreviewBtn.textContent = "Copy";
    }, 2000);
  } catch (err) {
    alert("Could not copy to clipboard: " + err);
  }
}

async function handleTagPending() {
  try {
    const res = await fetch("/api/tag-pending", { method: "POST" });
    const data = await res.json();
    alert(data.message || "Tagged pending-push!");
    await loadData();
  } catch (err) {
    alert("Tagging failed: " + err);
  }
}

async function handleCommit(tagPending) {
  const modelName = commitSubject.value.trim() || "gemini 3.8 flash high";
  const confirmMsg = tagPending
    ? `Create commit with message "${modelName}" and tag as pending-push?`
    : `Create commit with message "${modelName}"?`;

  if (!confirm(confirmMsg)) return;

  try {
    const res = await fetch("/api/commit", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        mode: activeCommitMode,
        tag_pending: tagPending,
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
