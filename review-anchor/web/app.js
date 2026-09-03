/* Review Anchor — browser view.
   Mirrors the TUI: the exchange file on disk is the source of truth, this is a
   window onto it. Nothing here talks to a model; the prompt leaves by
   clipboard and the response comes back the same way. */

const $ = (sel) => document.querySelector(sel);
const api = async (path, body) => {
  const res = await fetch(path, body === undefined
    ? {}
    : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const data = await res.json();
  if (data && data.doc) render(data);
  return data;
};

let state = null;
let selStart = null, selEnd = null;
let dirtyTimer = null;

/* ---------- rendering ---------- */

function render(next) {
  state = next;
  const { doc, git, exchange } = next;

  $('#branch').textContent = `${git.branch} → ${git.default}${git.dirty ? ' *' : ''}`;
  $('#bookmark').textContent = `pending-push ${git.pending_push || '—'}`;
  $('#stale').hidden = !exchange.stale;
  $('#docname').textContent = `${doc.rel} @${doc.rev}`;

  const log = $('#log');
  log.innerHTML = '';
  next.log.forEach((entry) => {
    const opt = document.createElement('option');
    opt.value = entry.number;
    opt.textContent = `${String(entry.number).padStart(4, '0')} ${entry.state === 'closed' ? '·' : '○'}`;
    opt.selected = entry.number === exchange.number;
    log.append(opt);
  });

  const anchored = new Set();
  exchange.anchors.forEach((a) => {
    for (let i = a.line; i < a.line + Math.max(1, a.count); i++) anchored.add(i);
  });

  const pane = $('#doc');
  const keepScroll = pane.scrollTop;
  pane.innerHTML = '';
  doc.lines.forEach((line) => {
    const row = document.createElement('div');
    row.className = `ln ${line.type}${line.type === 'heading' ? ' h' + line.level : ''}`;
    if (anchored.has(line.n)) row.classList.add('anchored');
    row.dataset.n = line.n;
    const g = document.createElement('span');
    g.className = 'g';
    g.textContent = String(line.n).padStart(3, '0');
    const t = document.createElement('span');
    t.className = 't';
    t.textContent = line.text || ' ';
    row.append(g, t);
    pane.append(row);
  });
  pane.scrollTop = keepScroll;

  if (document.activeElement !== $('#prompt')) $('#prompt').value = exchange.prompt;
  if (document.activeElement !== $('#response')) $('#response').value = exchange.response;
  if (document.activeElement !== $('#model')) $('#model').value = exchange.meta.model || '';
  if (document.activeElement !== $('#subject')) $('#subject').value = exchange.meta.subject || '';
  $('#commit').textContent = next.commit_message;
  $('#bare').checked = next.bare;
  $('#ancount').textContent = exchange.anchors.length;

  const list = $('#anchors');
  list.innerHTML = '';
  if (!exchange.anchors.length) list.innerHTML = '<p class="hint">No anchors yet. Click a line in the document.</p>';
  exchange.anchors.forEach((a) => {
    const box = document.createElement('div');
    box.className = 'anchor';
    const head = document.createElement('h4');
    head.textContent = a.header;
    const quote = document.createElement('blockquote');
    quote.textContent = a.quote.join('\n');
    const text = document.createElement('p');
    text.textContent = a.comment;
    const row = document.createElement('div');
    row.className = 'row';
    const go = document.createElement('button');
    go.textContent = 'show';
    go.onclick = () => scrollToLine(a.line);
    const del = document.createElement('button');
    del.textContent = 'remove';
    del.onclick = () => api('/api/anchor/delete', { line: a.line, number: exchange.number });
    row.append(go, del);
    box.append(head, quote, text, row);
    list.append(box);
  });

  if (next.message) status(next.message);
}

function status(text) { $('#status').textContent = text; }

function scrollToLine(n) {
  const row = document.querySelector(`.ln[data-n="${n}"]`);
  if (row) row.scrollIntoView({ block: 'center', behavior: 'smooth' });
}

function paintSelection() {
  document.querySelectorAll('.ln.sel').forEach((el) => el.classList.remove('sel'));
  if (selStart === null) return;
  const lo = Math.min(selStart, selEnd), hi = Math.max(selStart, selEnd);
  for (let n = lo; n <= hi; n++) {
    const row = document.querySelector(`.ln[data-n="${n}"]`);
    if (row) row.classList.add('sel');
  }
}

/* ---------- interaction ---------- */

$('#doc').addEventListener('click', (event) => {
  const row = event.target.closest('.ln');
  if (!row) return;
  const n = Number(row.dataset.n);
  if (event.shiftKey && selStart !== null) selEnd = n;
  else { selStart = n; selEnd = n; }
  paintSelection();
  if (!event.shiftKey) openComment();
});

function openComment() {
  const lo = Math.min(selStart, selEnd), hi = Math.max(selStart, selEnd);
  const quoted = state.doc.lines.filter((l) => l.n >= lo && l.n <= hi).map((l) => l.text);
  $('#commentwhere').textContent = `${state.doc.rel}:${lo}${hi > lo ? `,${hi - lo + 1}` : ''}`;
  $('#commentquote').textContent = quoted.join('\n');
  $('#commenttext').value = '';
  $('#commentbox').showModal();
  $('#commenttext').focus();
}

$('#commentbox').addEventListener('close', async () => {
  const box = $('#commentbox');
  if (box.returnValue !== 'ok') { selStart = selEnd = null; paintSelection(); return; }
  const lo = Math.min(selStart, selEnd), hi = Math.max(selStart, selEnd);
  const comment = $('#commenttext').value.trim();
  selStart = selEnd = null;
  paintSelection();
  if (!comment) return;
  await api('/api/anchor', { line: lo, count: hi - lo + 1, comment, number: state.exchange.number });
  status(`anchored ${state.doc.rel}:${lo}`);
});

document.querySelectorAll('.tabs button').forEach((btn) => {
  btn.onclick = () => {
    document.querySelectorAll('.tabs button').forEach((b) => b.classList.toggle('on', b === btn));
    document.querySelectorAll('.tabbody').forEach((body) => {
      body.hidden = body.dataset.tab !== btn.dataset.tab;
    });
  };
});

const saveSoon = () => {
  clearTimeout(dirtyTimer);
  dirtyTimer = setTimeout(async () => {
    await api('/api/exchange', {
      number: state.exchange.number,
      prompt: $('#prompt').value,
      response: $('#response').value,
      model: $('#model').value,
      subject: $('#subject').value,
    });
    status('saved ' + state.exchange.path);
  }, 500);
};
['#prompt', '#response', '#model', '#subject'].forEach((sel) => $(sel).addEventListener('input', saveSoon));

$('#copyprompt').onclick = async () => {
  const res = await api('/api/clip', { text: state.composed_prompt });
  status(`prompt + ${state.exchange.anchors.length} anchors copied via ${res.where}`);
};
$('#copycommit').onclick = async () => {
  const res = await api('/api/clip', { text: state.commit_message });
  status(`commit message copied via ${res.where}`);
};
$('#pasteresponse').onclick = async () => {
  const res = await api('/api/paste');
  if (!res.text || !res.text.trim()) return status('clipboard empty');
  $('#response').value = res.text.trim();
  saveSoon();
  status('response pasted');
};
$('#verify').onclick = async () => { await api('/api/verify', { number: state.exchange.number }); };
$('#bare').onchange = () => api('/api/bare', { bare: $('#bare').checked, number: state.exchange.number });
$('#docommit').onclick = async () => {
  if (!confirm('Commit this exchange?')) return;
  const res = await api('/api/commit', { number: state.exchange.number });
  if (res && res.ok === false) status('commit failed: ' + res.message);
};
$('#new').onclick = async () => {
  const title = prompt('Title for the new exchange');
  if (title === null) return;
  await api('/api/new', { title });
};
$('#log').onchange = () => api(`/api/state?n=${$('#log').value}`);

const size = $('#size');
size.oninput = () => {
  document.documentElement.style.setProperty('--doc-size', `${size.value}px`);
  $('#sizeout').textContent = `${size.value}px`;
  localStorage.setItem('ra-size', size.value);
};
$('#family').onchange = () => {
  document.documentElement.style.setProperty('--doc-family', $('#family').value);
  localStorage.setItem('ra-family', $('#family').selectedIndex);
};
const savedSize = localStorage.getItem('ra-size');
if (savedSize) { size.value = savedSize; size.oninput(); }
const savedFamily = localStorage.getItem('ra-family');
if (savedFamily) { $('#family').selectedIndex = Number(savedFamily); $('#family').onchange(); }

api('/api/state');
