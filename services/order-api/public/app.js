function prettyJson(data) {
  return JSON.stringify(data, null, 2);
}

async function safeJson(response) {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
}

const healthBadge = document.getElementById('healthBadge');
const inventoryTableBody = document.querySelector('#inventoryTable tbody');
const createOrderResult = document.getElementById('createOrderResult');
const getOrderResult = document.getElementById('getOrderResult');

document.getElementById('checkHealthBtn').addEventListener('click', async () => {
  try {
    const response = await fetch('/health');
    const data = await safeJson(response);

    if (response.ok) {
      healthBadge.textContent = `Healthy - ${data.timestamp || ''}`;
      healthBadge.className = 'badge success';
    } else {
      healthBadge.textContent = data.error || 'Unhealthy';
      healthBadge.className = 'badge error';
    }
  } catch (error) {
    healthBadge.textContent = `Error - ${error.message}`;
    healthBadge.className = 'badge error';
  }
});

document.getElementById('loadInventoryBtn').addEventListener('click', async () => {
  try {
    const response = await fetch('/inventory');
    const data = await safeJson(response);

    if (!response.ok) {
      inventoryTableBody.innerHTML = `<tr><td colspan="4">${data.error || 'Failed to load inventory'}</td></tr>`;
      return;
    }

    if (!Array.isArray(data) || data.length === 0) {
      inventoryTableBody.innerHTML = '<tr><td colspan="4">No inventory found</td></tr>';
      return;
    }

    inventoryTableBody.innerHTML = data.map(item => `
      <tr>
        <td>${item.id}</td>
        <td>${item.name}</td>
        <td>$${item.price}</td>
        <td>${item.stock}</td>
      </tr>
    `).join('');
  } catch (error) {
    inventoryTableBody.innerHTML = `<tr><td colspan="4">${error.message}</td></tr>`;
  }
});

document.getElementById('createOrderForm').addEventListener('submit', async (event) => {
  event.preventDefault();

  const payload = {
    customer_email: document.getElementById('customerEmail').value.trim(),
    items: [
      {
        product_id: document.getElementById('productId').value.trim(),
        qty: Number(document.getElementById('qty').value)
      }
    ]
  };

  try {
    const response = await fetch('/orders', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    const data = await safeJson(response);
    createOrderResult.textContent = prettyJson({
      statusCode: response.status,
      ...data
    });
  } catch (error) {
    createOrderResult.textContent = prettyJson({ error: error.message });
  }
});

document.getElementById('getOrderForm').addEventListener('submit', async (event) => {
  event.preventDefault();

  const orderId = document.getElementById('orderId').value.trim();

  try {
    const response = await fetch(`/orders/${orderId}`);
    const data = await safeJson(response);
    getOrderResult.textContent = prettyJson({
      statusCode: response.status,
      ...data
    });
  } catch (error) {
    getOrderResult.textContent = prettyJson({ error: error.message });
  }
});