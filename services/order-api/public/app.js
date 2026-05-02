const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
const PIPELINE_TICK_MS = 1000;

function prettyJson(data) {
  return JSON.stringify(data, null, 2);
}

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

async function safeJson(response) {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
}

function formatCurrency(value) {
  const amount = Number(value);
  if (Number.isNaN(amount)) {
    return `$${escapeHtml(value)}`;
  }

  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD'
  }).format(amount);
}

function formatClock(date = new Date()) {
  return new Intl.DateTimeFormat('en-US', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  }).format(date);
}

function stockClass(stock) {
  const amount = Number(stock);
  if (amount <= 0) return 'stock danger';
  if (amount < 25) return 'stock warning';
  return 'stock healthy';
}

function setButtonBusy(button, isBusy, busyText) {
  if (!button) return;

  const label = button.querySelector('span:last-child');

  if (isBusy) {
    button.dataset.defaultLabel = label ? label.textContent.trim() : button.textContent.trim();
    button.disabled = true;
    button.classList.add('is-busy');
    button.setAttribute('aria-busy', 'true');
    if (label && busyText) label.textContent = busyText;
    return;
  }

  button.disabled = false;
  button.classList.remove('is-busy');
  button.removeAttribute('aria-busy');

  if (button.dataset.defaultLabel && label) {
    label.textContent = button.dataset.defaultLabel;
  }
}

function renderResult(target, payload, state = 'default') {
  target.textContent = prettyJson(payload);
  target.className = `result ${state === 'compact' ? 'compact' : ''}`.trim();

  if (!target.animate || motionQuery.matches || state === 'compact') return;

  target.animate(
    [
      { opacity: 0.62, transform: 'translate3d(0, 6px, 0)' },
      { opacity: 1, transform: 'translate3d(0, 0, 0)' }
    ],
    { duration: 260, easing: 'cubic-bezier(0.16, 1, 0.3, 1)' }
  );
}

function addActivity(message) {
  const feed = document.getElementById('activityFeed');
  if (!feed) return;

  const item = document.createElement('li');
  const time = document.createElement('span');
  const text = document.createElement('span');

  time.className = 'activity-time';
  time.textContent = formatClock();
  text.textContent = message;

  item.append(time, text);
  feed.prepend(item);

  while (feed.children.length > 6) {
    feed.lastElementChild.remove();
  }
}

function setHealthState(kind, message, timestamp = '') {
  const healthBadge = document.getElementById('healthBadge');
  const serviceState = document.getElementById('serviceState');

  healthBadge.className = `status-chip ${kind}`;
  healthBadge.innerHTML = `
    <span class="status-dot"></span>
    <span>${escapeHtml(message)}</span>
  `;

  serviceState.textContent = message;

  if (timestamp) {
    healthBadge.title = `Last checked: ${timestamp}`;
  }
}

function renderInventorySkeleton() {
  const tableBody = document.querySelector('#inventoryTable tbody');
  tableBody.innerHTML = Array.from({ length: 4 }).map(() => `
    <tr class="skeleton-row">
      <td><span></span></td>
      <td><span></span></td>
      <td><span></span></td>
      <td><span></span></td>
    </tr>
  `).join('');
}

function renderInventoryRows(items) {
  const tableBody = document.querySelector('#inventoryTable tbody');

  if (!Array.isArray(items) || items.length === 0) {
    tableBody.innerHTML = `
      <tr>
        <td colspan="4" class="empty-cell">No inventory found.</td>
      </tr>
    `;
    return;
  }

  tableBody.innerHTML = items.map((item) => `
    <tr data-product-id="${escapeHtml(item.id)}" tabindex="0">
      <td><span class="mono">${escapeHtml(item.id)}</span></td>
      <td>${escapeHtml(item.name)}</td>
      <td>${formatCurrency(item.price)}</td>
      <td><span class="${stockClass(item.stock)}">${escapeHtml(item.stock)}</span></td>
    </tr>
  `).join('');
}

function setInventoryStatus(message, kind = 'neutral') {
  const inventoryStatus = document.getElementById('inventoryStatus');
  inventoryStatus.textContent = message;
  inventoryStatus.className = `inline-status ${kind}`;
}

function addRipple(event) {
  const button = event.currentTarget;
  const ripple = document.createElement('span');
  const rect = button.getBoundingClientRect();
  const size = Math.max(rect.width, rect.height);
  const hasPointer = event.clientX !== 0 || event.clientY !== 0;
  const x = hasPointer ? event.clientX - rect.left : rect.width / 2;
  const y = hasPointer ? event.clientY - rect.top : rect.height / 2;

  ripple.className = 'ripple';
  ripple.style.width = `${size}px`;
  ripple.style.height = `${size}px`;
  ripple.style.left = `${x - size / 2}px`;
  ripple.style.top = `${y - size / 2}px`;

  button.appendChild(ripple);
  ripple.addEventListener('animationend', () => ripple.remove());
}

function animateMetricNumber(element, value, suffix = '', prefix = '') {
  const target = Number(value);
  if (!element || Number.isNaN(target)) return;

  const metricKey = `${prefix}${target}${suffix}`;
  if (element.dataset.metricKey === metricKey) {
    element.textContent = metricKey;
    return;
  }

  element.dataset.metricKey = metricKey;

  if (motionQuery.matches) {
    element.textContent = metricKey;
    return;
  }

  const start = 0;
  const duration = 520;
  const startTime = performance.now();

  function easeOutCubic(progress) {
    return 1 - Math.pow(1 - progress, 3);
  }

  function step(now) {
    const progress = Math.min((now - startTime) / duration, 1);
    const current = Math.round(start + (target - start) * easeOutCubic(progress));
    element.textContent = `${prefix}${current}${suffix}`;

    if (progress < 1) {
      requestAnimationFrame(step);
    }
  }

  requestAnimationFrame(step);
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function normalizeStatus(status) {
  return String(status || 'PENDING').toUpperCase();
}

function isTerminalStatus(status) {
  return ['COMPLETED', 'FAILED', 'CANCELLED', 'ERROR'].includes(normalizeStatus(status));
}

function parseTimestamp(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function formatDateTime(value) {
  const date = parseTimestamp(value);
  if (!date) return 'None';
  return `${date.toLocaleDateString('en-US')} ${formatClock(date)}`;
}

function formatDuration(milliseconds) {
  const value = Math.max(0, Number(milliseconds) || 0);
  if (value < 1000) return `${Math.round(value)}ms`;
  if (value < 60000) return `${(value / 1000).toFixed(1)}s`;

  const minutes = Math.floor(value / 60000);
  const seconds = Math.round((value % 60000) / 1000);
  return `${minutes}m ${seconds}s`;
}

function getProcessingDuration(order) {
  if (!order) return null;

  if (order.pipeline && Number.isFinite(Number(order.pipeline.processing_duration_ms))) {
    return Number(order.pipeline.processing_duration_ms);
  }

  const createdAt = parseTimestamp(order.created_at);
  const processedAt = parseTimestamp(order.processed_at);

  if (!createdAt || !processedAt) return null;
  return processedAt.getTime() - createdAt.getTime();
}

function stateLabel(state) {
  const labels = {
    active: 'Live',
    complete: 'Done',
    failed: 'Failed',
    waiting: 'Waiting'
  };

  return labels[state] || state;
}

function shakeElement(element) {
  if (!element || motionQuery.matches) return;

  element.classList.remove('is-shaking');
  window.requestAnimationFrame(() => {
    element.classList.add('is-shaking');
    window.setTimeout(() => element.classList.remove('is-shaking'), 480);
  });
}

function initRevealObserver() {
  const targets = document.querySelectorAll('.reveal-card');

  targets.forEach((target, index) => {
    target.style.setProperty('--reveal-index', index);
  });

  if (motionQuery.matches || !('IntersectionObserver' in window)) {
    targets.forEach((target) => target.classList.add('is-visible'));
    return;
  }

  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('is-visible');
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.1 });

  targets.forEach((target) => observer.observe(target));
}

function initClock() {
  const systemTime = document.getElementById('systemTime');

  function updateTime() {
    systemTime.textContent = `Local time ${formatClock()}`;
    window.setTimeout(updateTime, 1000);
  }

  updateTime();
}

const checkHealthBtn = document.getElementById('checkHealthBtn');
const loadInventoryBtn = document.getElementById('loadInventoryBtn');
const inventoryTableBody = document.querySelector('#inventoryTable tbody');
const createOrderResult = document.getElementById('createOrderResult');
const getOrderResult = document.getElementById('getOrderResult');
const inventoryCount = document.getElementById('inventoryCount');
const lastOrderId = document.getElementById('lastOrderId');
const pipelineState = document.getElementById('pipelineState');
const invoiceActions = document.getElementById('invoiceActions');
const invoiceDownloadLink = document.getElementById('invoiceDownloadLink');
const invoiceDownloadMeta = document.getElementById('invoiceDownloadMeta');
const pipelineOverlay = document.getElementById('orderPipelineOverlay');
const closePipelineBtn = document.getElementById('closePipelineBtn');
const pipelineProgressBar = document.getElementById('pipelineProgressBar');
const pipelinePercent = document.getElementById('pipelinePercent');
const pipelineSummary = document.getElementById('pipelineSummary');
const pipelineSteps = document.getElementById('pipelineSteps');
const pipelineLivePayload = document.getElementById('pipelineLivePayload');
const inlinePipelineBadge = document.getElementById('inlinePipelineBadge');
const inlinePipelineBar = document.getElementById('inlinePipelineBar');
const inlinePipelinePercent = document.getElementById('inlinePipelinePercent');
const inlinePipelineSummary = document.getElementById('inlinePipelineSummary');

const ORDER_TRACE_POLL_MS = 1250;
const ORDER_TRACE_TIMEOUT_MS = 180000;

let activePipelineTrace = null;
let pipelineRunId = 0;
let pipelineTimerId = null;
let pipelinePollTimerId = null;
let invoiceDownloadOrderId = null;

function resetInvoiceDownload(message = 'Available after completion.') {
  invoiceDownloadOrderId = null;

  if (invoiceActions) {
    invoiceActions.classList.add('is-hidden');
  }

  if (invoiceDownloadLink) {
    invoiceDownloadLink.href = '#';
    invoiceDownloadLink.setAttribute('aria-disabled', 'true');
  }

  if (invoiceDownloadMeta) {
    invoiceDownloadMeta.textContent = message;
  }
}

function setInvoiceDownloadPending(message) {
  if (invoiceActions) {
    invoiceActions.classList.remove('is-hidden');
  }

  if (invoiceDownloadLink) {
    invoiceDownloadLink.href = '#';
    invoiceDownloadLink.setAttribute('aria-disabled', 'true');
  }

  if (invoiceDownloadMeta) {
    invoiceDownloadMeta.textContent = message;
  }
}

function showInvoiceDownload(orderId, invoiceData) {
  invoiceDownloadOrderId = String(orderId);

  if (invoiceActions) {
    invoiceActions.classList.remove('is-hidden');
  }

  if (invoiceDownloadLink) {
    invoiceDownloadLink.href = invoiceData.invoice_url;
    invoiceDownloadLink.removeAttribute('aria-disabled');
  }

  if (invoiceDownloadMeta) {
    const minutes = Math.max(1, Math.round((invoiceData.expires_in || 300) / 60));
    invoiceDownloadMeta.textContent = `Pre-signed S3 link expires in ${minutes} minutes.`;
  }
}

async function loadInvoiceDownload(orderId) {
  if (!orderId) return;
  if (invoiceDownloadOrderId === String(orderId)) return;

  setInvoiceDownloadPending('Preparing secure S3 invoice link...');

  try {
    const response = await fetch(`/orders/${encodeURIComponent(orderId)}/invoice`);
    const data = await safeJson(response);

    if (!response.ok || !data.invoice_url) {
      setInvoiceDownloadPending(data.error || 'Invoice link is not available yet.');
      addActivity(`Invoice link for order #${orderId} is not ready.`);
      return;
    }

    showInvoiceDownload(orderId, data);
    addActivity(`Invoice link ready for order #${orderId}.`);
  } catch (error) {
    setInvoiceDownloadPending(`Invoice link error: ${error.message}`);
    addActivity(`Invoice link for order #${orderId} could not be created.`);
  }
}

function updateInvoiceDownloadForOrder(order) {
  if (normalizeStatus(order?.status) === 'COMPLETED' && order?.invoice_key) {
    loadInvoiceDownload(order.id);
    return;
  }

  resetInvoiceDownload('Available after completion.');
}

function openPipelineDialog() {
  if (!pipelineOverlay) return;
  pipelineOverlay.classList.add('is-open');
  pipelineOverlay.setAttribute('aria-hidden', 'false');
}

function closePipelineDialog() {
  if (!pipelineOverlay) return;
  pipelineOverlay.classList.remove('is-open');
  pipelineOverlay.setAttribute('aria-hidden', 'true');
}

function clearPipelineTimers() {
  if (pipelineTimerId) {
    window.clearTimeout(pipelineTimerId);
    pipelineTimerId = null;
  }

  if (pipelinePollTimerId) {
    window.clearTimeout(pipelinePollTimerId);
    pipelinePollTimerId = null;
  }
}

function beginPipelineTrace(requestPayload) {
  clearPipelineTimers();
  pipelineRunId += 1;

  activePipelineTrace = {
    runId: pipelineRunId,
    startedAt: Date.now(),
    postStartedAt: performance.now(),
    requestPayload,
    createResponse: null,
    order: null,
    orderId: null,
    status: 'SUBMITTING',
    pollCount: 0,
    lastCheckedAt: null,
    postDurationMs: null,
    terminal: false,
    timedOut: false,
    error: null,
    lastActivityStatus: null
  };

  openPipelineDialog();
  renderPipelineTrace(activePipelineTrace);
  startPipelineTicker(pipelineRunId);

  return pipelineRunId;
}

function startPipelineTicker(runId) {
  if (pipelineTimerId) {
    window.clearTimeout(pipelineTimerId);
  }

  function tick() {
    if (!activePipelineTrace || activePipelineTrace.runId !== runId) return;
    renderPipelineTrace(activePipelineTrace, {
      skipPayload: true,
      skipSteps: true
    });

    if (activePipelineTrace.terminal || activePipelineTrace.timedOut || activePipelineTrace.error) {
      pipelineTimerId = null;
      return;
    }

    pipelineTimerId = window.setTimeout(tick, PIPELINE_TICK_MS);
  }

  tick();
}

function elapsedLabel(trace) {
  const exactDuration = getProcessingDuration(trace.order);
  if (exactDuration !== null && isTerminalStatus(trace.order?.status)) {
    return formatDuration(exactDuration);
  }

  return formatDuration(Date.now() - trace.startedAt);
}

function statusForTrace(trace) {
  if (trace.error) return 'ERROR';
  if (trace.timedOut) return normalizeStatus(trace.order?.status || trace.status);
  return normalizeStatus(trace.order?.status || trace.status);
}

function buildPipelineSteps(trace) {
  const status = statusForTrace(trace);
  const order = trace.order || {};
  const createResponse = trace.createResponse || {};
  const createdAt = order.created_at || createResponse.created_at;
  const queuedAt = createResponse.queued_at;
  const processedAt = order.processed_at;
  const hasOrderId = Boolean(trace.orderId || order.id);
  const failed = status === 'FAILED' || status === 'ERROR';
  const completed = status === 'COMPLETED';
  const processing = status === 'PROCESSING';

  const postState = trace.error && !trace.createResponse ? 'failed' : trace.createResponse ? 'complete' : 'active';
  const rdsState = failed && !hasOrderId ? 'failed' : hasOrderId ? 'complete' : 'waiting';
  const queueState = failed && !hasOrderId ? 'failed' : trace.createResponse ? 'complete' : 'waiting';
  const lambdaState = failed ? 'failed' : completed ? 'complete' : (processing || status === 'PENDING') ? 'active' : 'waiting';
  const artifactState = failed ? 'failed' : completed ? 'complete' : 'waiting';

  return [
    {
      title: 'POST /orders',
      detail: trace.postDurationMs === null
        ? 'Submitting order request'
        : `API response in ${formatDuration(trace.postDurationMs)}`,
      state: postState
    },
    {
      title: 'RDS order row',
      detail: createdAt ? `Created ${formatDateTime(createdAt)}` : 'Waiting for order id',
      state: rdsState
    },
    {
      title: 'SQS event queued',
      detail: queuedAt ? `Queued ${formatDateTime(queuedAt)}` : 'Waiting for queue acknowledgement',
      state: queueState
    },
    {
      title: 'Lambda processor',
      detail: completed
        ? `Processed ${formatDateTime(processedAt)}`
        : processing
          ? 'Lambda is processing the order'
          : status === 'PENDING'
            ? 'Waiting for Lambda trigger'
            : trace.error || 'Waiting for order status',
      state: lambdaState
    },
    {
      title: 'Invoice and audit',
      detail: order.invoice_key || order.payment_ref || (completed ? 'Artifacts recorded' : 'Waiting for final DB update'),
      state: artifactState
    }
  ];
}

function pipelinePercentFromSteps(trace, steps) {
  if (trace.error || statusForTrace(trace) === 'FAILED') return 100;
  if (statusForTrace(trace) === 'COMPLETED') return 100;

  const completeCount = steps.filter((step) => step.state === 'complete').length;
  const hasActive = steps.some((step) => step.state === 'active');
  const basePercent = Math.round((completeCount / steps.length) * 100);
  return clamp(basePercent + (hasActive ? 8 : 0), trace.createResponse ? 20 : 8, 95);
}

function renderPipelineSummary(target, trace, includeLastCheck) {
  if (!target) return;

  const status = statusForTrace(trace);
  const summaryItems = [
    ['Order', trace.orderId || trace.order?.id ? `#${trace.orderId || trace.order.id}` : 'Pending'],
    ['Status', trace.timedOut ? `${status} (still live)` : status],
    ['Elapsed', elapsedLabel(trace)]
  ];

  if (includeLastCheck) {
    summaryItems.push(['Last check', trace.lastCheckedAt ? formatClock(new Date(trace.lastCheckedAt)) : 'None']);
  }

  target.innerHTML = summaryItems.map(([label, value]) => `
    <div>
      <span>${escapeHtml(label)}</span>
      <strong>${escapeHtml(value)}</strong>
    </div>
  `).join('');
}

function renderPipelineSteps(steps) {
  if (!pipelineSteps) return;

  pipelineSteps.innerHTML = steps.map((step, index) => `
    <li class="pipeline-step ${escapeHtml(step.state)}">
      <span class="pipeline-step-marker">${index + 1}</span>
      <span>
        <span class="pipeline-step-title">${escapeHtml(step.title)}</span>
        <span class="pipeline-step-detail">${escapeHtml(step.detail)}</span>
      </span>
      <span class="pipeline-step-state">${escapeHtml(stateLabel(step.state))}</span>
    </li>
  `).join('');
}

function tracePayload(trace) {
  return {
    request: trace.requestPayload,
    create_response: trace.createResponse,
    latest_order: trace.order,
    status: statusForTrace(trace),
    poll_count: trace.pollCount,
    elapsed_ms: Math.round(Date.now() - trace.startedAt),
    exact_processing_ms: getProcessingDuration(trace.order),
    last_checked_at: trace.lastCheckedAt ? new Date(trace.lastCheckedAt).toISOString() : null,
    last_network_error: trace.lastNetworkError || null,
    error: trace.error
  };
}

function renderPipelineTrace(trace, options = {}) {
  if (!trace) return;

  const steps = buildPipelineSteps(trace);
  const percent = trace.order?.pipeline?.percent ?? pipelinePercentFromSteps(trace, steps);
  const progress = clamp(Number(percent) || 0, 0, 100);
  const failed = trace.error || statusForTrace(trace) === 'FAILED';
  const status = statusForTrace(trace);

  [pipelineProgressBar, inlinePipelineBar].forEach((bar) => {
    if (!bar) return;
    bar.style.width = `${progress}%`;
    bar.classList.toggle('failed', Boolean(failed));
  });

  if (pipelinePercent) pipelinePercent.textContent = `${Math.round(progress)}%`;
  if (inlinePipelinePercent) inlinePipelinePercent.textContent = `${Math.round(progress)}%`;
  if (inlinePipelineBadge) inlinePipelineBadge.textContent = trace.timedOut ? 'Still processing' : status;

  renderPipelineSummary(pipelineSummary, trace, true);
  renderPipelineSummary(inlinePipelineSummary, trace, false);
  if (!options.skipSteps) {
    renderPipelineSteps(steps);
  }

  if (pipelineLivePayload && !options.skipPayload) {
    pipelineLivePayload.textContent = prettyJson(tracePayload(trace));
  }
}

async function fetchOrderSnapshot(orderId) {
  const response = await fetch(`/orders/${encodeURIComponent(orderId)}`);
  const data = await safeJson(response);

  return {
    response,
    data,
    result: {
      statusCode: response.status,
      ...data
    }
  };
}

function recordPipelineActivity(trace, message, status) {
  if (trace.lastActivityStatus === status) return;
  trace.lastActivityStatus = status;
  addActivity(message);
}

function finishPipelineButton(button) {
  if (button) {
    setButtonBusy(button, false);
  }
}

function pollOrderUntilTerminal(orderId, runId, options = {}) {
  if (pipelinePollTimerId) {
    window.clearTimeout(pipelinePollTimerId);
    pipelinePollTimerId = null;
  }

  async function poll() {
    const trace = activePipelineTrace;
    if (!trace || trace.runId !== runId) return;

    if (Date.now() - trace.startedAt > ORDER_TRACE_TIMEOUT_MS) {
      trace.timedOut = true;
      trace.status = trace.order?.status || 'PENDING';
      renderPipelineTrace(trace);
      finishPipelineButton(options.busyButton);
      addActivity(`Order #${orderId} is still processing.`);
      return;
    }

    trace.pollCount += 1;
    trace.lastCheckedAt = Date.now();
    renderPipelineTrace(trace);

    try {
      const { response, data, result } = await fetchOrderSnapshot(orderId);

      if (!response.ok) {
        trace.error = data.error || `Lookup failed with HTTP ${response.status}`;
        trace.status = 'ERROR';
        renderResult(getOrderResult, result, 'compact');
        renderPipelineTrace(trace);
        finishPipelineButton(options.busyButton);
        addActivity(`Order #${orderId} trace failed.`);
        return;
      }

      const previousStatus = statusForTrace(trace);
      trace.order = data;
      trace.status = normalizeStatus(data.status);
      trace.orderId = data.id || orderId;
      trace.error = null;
      renderResult(getOrderResult, result, 'compact');
      animateMetricNumber(lastOrderId, trace.orderId, '', '#');
      pipelineState.textContent = `Order ${trace.status}`;

      if (trace.status !== previousStatus) {
        recordPipelineActivity(trace, `Order #${orderId} is ${trace.status}.`, trace.status);
      }

      if (isTerminalStatus(trace.status)) {
        trace.terminal = true;
        renderPipelineTrace(trace);
        updateInvoiceDownloadForOrder(data);
        finishPipelineButton(options.busyButton);
        return;
      }
    } catch (error) {
      trace.error = null;
      trace.lastNetworkError = error.message;
      recordPipelineActivity(trace, `Order #${orderId} trace retrying after network error.`, 'NETWORK_ERROR');
    }

    renderPipelineTrace(trace);
    pipelinePollTimerId = window.setTimeout(poll, ORDER_TRACE_POLL_MS);
  }

  poll();
}

resetInvoiceDownload();
initRevealObserver();
initClock();

document.querySelectorAll('.button').forEach((button) => {
  button.addEventListener('click', addRipple);
});

closePipelineBtn?.addEventListener('click', closePipelineDialog);

invoiceDownloadLink?.addEventListener('click', (event) => {
  if (invoiceDownloadLink.getAttribute('aria-disabled') === 'true') {
    event.preventDefault();
  }
});

pipelineOverlay?.addEventListener('click', (event) => {
  if (event.target === pipelineOverlay) {
    closePipelineDialog();
  }
});

window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    closePipelineDialog();
  }
});

document.querySelectorAll('input').forEach((input) => {
  input.addEventListener('invalid', () => shakeElement(input.closest('form')));
  input.addEventListener('input', () => input.classList.remove('is-invalid'));
});

checkHealthBtn.addEventListener('click', async () => {
  setButtonBusy(checkHealthBtn, true, 'Checking');
  setHealthState('neutral', 'Checking');
  addActivity('Health check started.');

  try {
    const response = await fetch('/health');
    const data = await safeJson(response);

    if (response.ok) {
      setHealthState('success', 'Healthy', data.timestamp || '');
      pipelineState.textContent = 'API reachable';
      addActivity('Health check passed.');
      return;
    }

    setHealthState('error', data.error || 'Unhealthy');
    pipelineState.textContent = 'Needs attention';
    addActivity('Health check returned an error.');
  } catch (error) {
    setHealthState('error', `Error: ${error.message}`);
    pipelineState.textContent = 'Network error';
    addActivity('Health check could not reach the API.');
  } finally {
    setButtonBusy(checkHealthBtn, false);
  }
});

loadInventoryBtn.addEventListener('click', async () => {
  setButtonBusy(loadInventoryBtn, true, 'Loading');
  setInventoryStatus('Loading inventory from API...', 'neutral');
  renderInventorySkeleton();
  addActivity('Inventory load requested.');

  try {
    const response = await fetch('/inventory');
    const data = await safeJson(response);

    if (!response.ok) {
      renderInventoryRows([]);
      inventoryCount.textContent = 'Error';
      setInventoryStatus(data.error || 'Failed to load inventory.', 'error');
      addActivity('Inventory load failed.');
      return;
    }

    renderInventoryRows(data);
    animateMetricNumber(inventoryCount, data.length, ' products');
    setInventoryStatus(`Inventory loaded successfully. ${data.length} products available.`, 'success');
    addActivity(`Inventory loaded: ${data.length} products.`);
  } catch (error) {
    renderInventoryRows([]);
    inventoryCount.textContent = 'Error';
    setInventoryStatus(error.message, 'error');
    addActivity('Inventory request could not reach the API.');
  } finally {
    setButtonBusy(loadInventoryBtn, false);
  }
});

inventoryTableBody.addEventListener('click', (event) => {
  const row = event.target.closest('tr[data-product-id]');
  if (!row) return;

  document.getElementById('productId').value = row.dataset.productId;
  document.getElementById('qty').value = '1';
  row.classList.add('selected-row');
  window.setTimeout(() => row.classList.remove('selected-row'), 700);
  addActivity(`Selected ${row.dataset.productId} for checkout.`);
});

inventoryTableBody.addEventListener('keydown', (event) => {
  if (event.key !== 'Enter') return;

  const row = event.target.closest('tr[data-product-id]');
  if (!row) return;

  document.getElementById('productId').value = row.dataset.productId;
  document.getElementById('qty').value = '1';
  addActivity(`Selected ${row.dataset.productId} for checkout.`);
});

document.getElementById('createOrderForm').addEventListener('submit', async (event) => {
  event.preventDefault();

  const form = event.currentTarget;
  const submitButton = form.querySelector('button[type="submit"]');
  const customerEmail = document.getElementById('customerEmail').value.trim();
  const productId = document.getElementById('productId').value.trim();
  const quantity = Number(document.getElementById('qty').value);

  if (!customerEmail || !productId || !quantity || quantity <= 0) {
    renderResult(createOrderResult, {
      error: 'customer_email, product_id, and qty > 0 are required'
    });
    shakeElement(form);
    addActivity('Order form validation failed.');
    return;
  }

  const payload = {
    customer_email: customerEmail,
    items: [
      {
        product_id: productId,
        qty: quantity
      }
    ]
  };

  resetInvoiceDownload('Available after completion.');
  setButtonBusy(submitButton, true, 'Tracing');
  pipelineState.textContent = 'Submitting order';
  addActivity(`Submitting order for ${productId}.`);

  const runId = beginPipelineTrace(payload);
  let releaseSubmitButton = true;

  try {
    const trace = activePipelineTrace;
    if (trace && trace.runId === runId) {
      trace.postStartedAt = performance.now();
      renderPipelineTrace(trace);
    }

    const response = await fetch('/orders', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    const data = await safeJson(response);
    const activeTrace = activePipelineTrace;

    if (activeTrace && activeTrace.runId === runId) {
      activeTrace.postDurationMs = performance.now() - activeTrace.postStartedAt;
      activeTrace.createResponse = data;
      activeTrace.status = normalizeStatus(data.status || (response.ok ? 'PENDING' : 'ERROR'));
      activeTrace.orderId = data.order_id || data.id || null;
      activeTrace.error = response.ok ? null : (data.error || `HTTP ${response.status}`);
      activeTrace.lastCheckedAt = Date.now();
    }

    const result = {
      statusCode: response.status,
      ...data
    };

    renderResult(createOrderResult, result);

    if (response.status === 201 && data.order_id) {
      animateMetricNumber(lastOrderId, data.order_id, '', '#');
      document.getElementById('orderId').value = data.order_id;
      pipelineState.textContent = 'Order queued';
      addActivity(`Order #${data.order_id} queued.`);
      renderPipelineTrace(activePipelineTrace);
      releaseSubmitButton = false;
      pollOrderUntilTerminal(data.order_id, runId, { busyButton: submitButton });
      return;
    }

    pipelineState.textContent = response.ok ? 'Order response' : 'Order failed';
    addActivity(response.ok ? 'Order response received.' : 'Order request failed.');
    renderPipelineTrace(activePipelineTrace);
  } catch (error) {
    renderResult(createOrderResult, { error: error.message });
    pipelineState.textContent = 'Order error';
    if (activePipelineTrace && activePipelineTrace.runId === runId) {
      activePipelineTrace.error = error.message;
      activePipelineTrace.status = 'ERROR';
      activePipelineTrace.postDurationMs = performance.now() - activePipelineTrace.postStartedAt;
      renderPipelineTrace(activePipelineTrace);
    }
    addActivity('Order request could not reach the API.');
  } finally {
    if (releaseSubmitButton) {
      setButtonBusy(submitButton, false);
    }
  }
});

document.getElementById('orderFormReset').addEventListener('click', () => {
  createOrderResult.textContent = 'No order created yet.';
  resetInvoiceDownload('Available after completion.');
  addActivity('Order form reset.');
});

document.getElementById('getOrderForm').addEventListener('submit', async (event) => {
  event.preventDefault();

  const form = event.currentTarget;
  const submitButton = form.querySelector('button[type="submit"]');
  const orderId = document.getElementById('orderId').value.trim();

  if (!orderId) {
    renderResult(getOrderResult, { error: 'Order ID is required' }, 'compact');
    shakeElement(form);
    addActivity('Order lookup validation failed.');
    return;
  }

  setButtonBusy(submitButton, true, 'Fetching');
  pipelineState.textContent = 'Checking order';
  resetInvoiceDownload('Checking invoice availability...');
  addActivity(`Looking up order #${orderId}.`);

  try {
    const response = await fetch(`/orders/${encodeURIComponent(orderId)}`);
    const data = await safeJson(response);
    const result = {
      statusCode: response.status,
      ...data
    };

    renderResult(getOrderResult, result, 'compact');

    if (response.ok && data.status) {
      animateMetricNumber(lastOrderId, orderId, '', '#');
      pipelineState.textContent = `Order ${data.status}`;
      if (activePipelineTrace && String(activePipelineTrace.orderId) === String(orderId)) {
        activePipelineTrace.order = data;
        activePipelineTrace.status = normalizeStatus(data.status);
        activePipelineTrace.lastCheckedAt = Date.now();
        activePipelineTrace.terminal = isTerminalStatus(data.status);
        renderPipelineTrace(activePipelineTrace);
      }
      updateInvoiceDownloadForOrder(data);
      addActivity(`Order #${orderId} is ${data.status}.`);
      return;
    }

    pipelineState.textContent = response.ok ? 'Order found' : 'Order lookup failed';
    addActivity(response.ok ? `Order #${orderId} response received.` : `Order #${orderId} lookup failed.`);
  } catch (error) {
    renderResult(getOrderResult, { error: error.message }, 'compact');
    pipelineState.textContent = 'Lookup error';
    addActivity('Order lookup could not reach the API.');
  } finally {
    setButtonBusy(submitButton, false);
  }
});
