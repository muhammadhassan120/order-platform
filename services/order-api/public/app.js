const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
const finePointerQuery = window.matchMedia('(pointer: fine)');

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

  if (!target.animate || motionQuery.matches) return;

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

  tableBody.innerHTML = items.map((item, index) => `
    <tr data-product-id="${escapeHtml(item.id)}" tabindex="0" style="--row-index:${index}">
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

  if (motionQuery.matches) {
    element.textContent = `${prefix}${target}${suffix}`;
    return;
  }

  const start = 0;
  const duration = 1200;
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

function initSurfaceGlow() {
  if (!finePointerQuery.matches) return;

  document.querySelectorAll('.interactive-surface').forEach((surface) => {
    surface.addEventListener('pointermove', (event) => {
      const rect = surface.getBoundingClientRect();
      surface.style.setProperty('--x', `${event.clientX - rect.left}px`);
      surface.style.setProperty('--y', `${event.clientY - rect.top}px`);
    });
  });
}

function initCursorGlow() {
  const glow = document.querySelector('.cursor-glow');
  if (!glow || !finePointerQuery.matches || motionQuery.matches) return;

  let pointerX = window.innerWidth / 2;
  let pointerY = window.innerHeight / 2;
  let glowX = pointerX;
  let glowY = pointerY;

  window.addEventListener('pointermove', (event) => {
    pointerX = event.clientX;
    pointerY = event.clientY;
  }, { passive: true });

  function updateGlow() {
    glowX += (pointerX - glowX) * 0.18;
    glowY += (pointerY - glowY) * 0.18;
    glow.style.transform = `translate3d(${glowX}px, ${glowY}px, 0) translate3d(-50%, -50%, 0)`;
    requestAnimationFrame(updateGlow);
  }

  updateGlow();
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

initRevealObserver();
initSurfaceGlow();
initCursorGlow();
initClock();

document.querySelectorAll('.button').forEach((button) => {
  button.addEventListener('click', addRipple);
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

  setButtonBusy(submitButton, true, 'Creating');
  pipelineState.textContent = 'Submitting order';
  addActivity(`Submitting order for ${productId}.`);

  try {
    const response = await fetch('/orders', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    const data = await safeJson(response);
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
      return;
    }

    pipelineState.textContent = response.ok ? 'Order response' : 'Order failed';
    addActivity(response.ok ? 'Order response received.' : 'Order request failed.');
  } catch (error) {
    renderResult(createOrderResult, { error: error.message });
    pipelineState.textContent = 'Order error';
    addActivity('Order request could not reach the API.');
  } finally {
    setButtonBusy(submitButton, false);
  }
});

document.getElementById('orderFormReset').addEventListener('click', () => {
  createOrderResult.textContent = 'No order created yet.';
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
