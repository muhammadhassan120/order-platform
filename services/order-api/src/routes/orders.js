const express = require('express');
const { GetObjectCommand } = require('@aws-sdk/client-s3');
const { SendMessageCommand } = require('@aws-sdk/client-sqs');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');

const INVOICE_URL_EXPIRES_IN_SECONDS = 300;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function toIso(value) {
  if (!value) return null;
  if (value instanceof Date) return value.toISOString();

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function durationMs(start, end) {
  const startedAt = start ? new Date(start) : null;
  const endedAt = end ? new Date(end) : null;

  if (!startedAt || !endedAt) return null;
  if (Number.isNaN(startedAt.getTime()) || Number.isNaN(endedAt.getTime())) return null;

  return Math.max(0, endedAt.getTime() - startedAt.getTime());
}

function buildOrderPipeline(order, queuedAt = null) {
  const status = String(order.status || 'PENDING').toUpperCase();
  const createdAt = toIso(order.created_at);
  const processedAt = toIso(order.processed_at);
  const isCompleted = status === 'COMPLETED';
  const isFailed = status === 'FAILED';
  const isProcessing = status === 'PROCESSING';

  const stages = [
    {
      key: 'api',
      label: 'API accepted order',
      state: createdAt ? 'complete' : 'active',
      timestamp: createdAt
    },
    {
      key: 'rds',
      label: 'RDS order row created',
      state: createdAt ? 'complete' : 'waiting',
      timestamp: createdAt
    },
    {
      key: 'sqs',
      label: 'SQS order event queued',
      state: isFailed ? 'failed' : 'complete',
      timestamp: queuedAt ? toIso(queuedAt) : null
    },
    {
      key: 'lambda',
      label: 'Lambda processor',
      state: isFailed ? 'failed' : isCompleted ? 'complete' : (isProcessing || status === 'PENDING') ? 'active' : 'waiting',
      timestamp: processedAt
    },
    {
      key: 'artifacts',
      label: 'Audit and invoice recorded',
      state: isFailed ? 'failed' : isCompleted ? 'complete' : 'waiting',
      timestamp: processedAt,
      detail: order.invoice_key || order.payment_ref || null
    }
  ];

  const completeCount = stages.filter((stage) => stage.state === 'complete').length;
  const hasActiveStage = stages.some((stage) => stage.state === 'active');
  const percent = isCompleted || isFailed
    ? 100
    : Math.min(95, Math.round((completeCount / stages.length) * 100) + (hasActiveStage ? 8 : 0));

  return {
    status,
    percent,
    terminal: isCompleted || isFailed,
    processing_duration_ms: durationMs(order.created_at, order.processed_at),
    stages
  };
}

function withPipeline(order, queuedAt = null) {
  return {
    ...order,
    pipeline: buildOrderPipeline(order, queuedAt)
  };
}

function buildInvoiceFileName(orderId, invoiceKey) {
  const extension = invoiceKey.split('.').pop() || 'txt';
  return `order-${orderId}-invoice.${extension}`;
}

function isValidInvoiceKey(invoiceKey) {
  return typeof invoiceKey === 'string' &&
    invoiceKey.startsWith('invoices/') &&
    !invoiceKey.includes('..') &&
    !invoiceKey.includes('\\');
}

function validateOrderPayload(body) {
  const customerEmail = String(body?.customer_email || '').trim();

  if (!EMAIL_PATTERN.test(customerEmail)) {
    return { error: 'customer_email must be a valid email address' };
  }

  if (!Array.isArray(body?.items) || body.items.length === 0) {
    return { error: 'items[] must contain at least one item' };
  }

  const items = [];

  for (const item of body.items) {
    const productId = String(item?.product_id || '').trim();
    const qty = Number(item?.qty);

    if (!productId || !Number.isInteger(qty) || qty <= 0) {
      return { error: 'Each item must contain product_id and a positive integer qty' };
    }

    items.push({
      product_id: productId,
      qty
    });
  }

  return {
    customer_email: customerEmail,
    items
  };
}

async function markOrderFailedAndRestoreStock(poolPromise, orderId, items) {
  const pool = await poolPromise();
  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    for (const item of items) {
      await client.query(
        `
        UPDATE products
        SET stock = stock + $1
        WHERE id = $2
        `,
        [item.qty, item.product_id]
      );
    }

    await client.query(
      `
      UPDATE orders
      SET status = 'FAILED',
          processed_at = NOW()
      WHERE id = $1
      `,
      [orderId]
    );

    await client.query('COMMIT');
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    throw err;
  } finally {
    client.release();
  }
}

async function findOrder(poolPromise, orderId) {
  const pool = await poolPromise();
  const { rows } = await pool.query(
    `
    SELECT id, customer_email, items, total, status, created_at, processed_at, payment_ref, invoice_key
    FROM orders
    WHERE id = $1
    `,
    [orderId]
  );

  return rows[0] || null;
}

module.exports = function createOrdersRouter({
  poolPromise,
  sqsClient,
  orderQueueUrl,
  s3Client,
  invoiceBucket,
  getSignedUrlFn = getSignedUrl
}) {
  const router = express.Router();

  router.post('/', async (req, res) => {
    const validation = validateOrderPayload(req.body);

    if (validation.error) {
      return res.status(400).json({
        error: validation.error
      });
    }

    if (!orderQueueUrl) {
      return res.status(500).json({ error: 'ORDER_QUEUE_URL is not configured' });
    }

    if (!sqsClient) {
      return res.status(500).json({ error: 'SQS client is not configured' });
    }

    const { customer_email, items } = validation;
    const pool = await poolPromise();
    const client = await pool.connect();
    let order = null;
    let transactionOpen = false;

    try {
      await client.query('BEGIN');
      transactionOpen = true;

      let total = 0;

      for (const item of items) {
        const { rows } = await client.query(
          `
          SELECT id, price, stock
          FROM products
          WHERE id = $1
          FOR UPDATE
          `,
          [item.product_id]
        );

        if (!rows.length) {
          throw new Error(`Product ${item.product_id} not found`);
        }

        const price = Number(rows[0].price);

        if (!Number.isFinite(price)) {
          throw new Error(`Invalid price for ${item.product_id}`);
        }

        if (rows[0].stock < item.qty) {
          throw new Error(`Insufficient stock for ${item.product_id}`);
        }

        total += price * item.qty;

        await client.query(
          `
          UPDATE products
          SET stock = stock - $1
          WHERE id = $2
          `,
          [item.qty, item.product_id]
        );
      }

      if (!Number.isFinite(total)) {
        throw new Error('Order total must be finite');
      }

      const { rows: [createdOrder] } = await client.query(
        `
        INSERT INTO orders (customer_email, items, total, status, created_at)
        VALUES ($1, $2, $3, 'PENDING', NOW())
        RETURNING id, status, total, created_at
        `,
        [customer_email, JSON.stringify(items), total]
      );
      order = createdOrder;

      await client.query('COMMIT');
      transactionOpen = false;

      await sqsClient.send(new SendMessageCommand({
        QueueUrl: orderQueueUrl,
        MessageBody: JSON.stringify({
          order_id: order.id,
          customer_email,
          items,
          total: order.total,
          created_at: order.created_at
        }),
        MessageAttributes: {
          event_type: {
            DataType: 'String',
            StringValue: 'ORDER_CREATED'
          }
        }
      }));

      const queuedAt = new Date().toISOString();

      return res.status(201).json({
        order_id: order.id,
        status: 'PENDING',
        total: order.total,
        created_at: order.created_at,
        queued_at: queuedAt,
        pipeline: buildOrderPipeline({ ...order, status: 'PENDING' }, queuedAt)
      });
    } catch (err) {
      if (transactionOpen) {
        try {
          await client.query('ROLLBACK');
        } catch (_) {}
      }

      console.error('Order creation failed:', err);

      if (order?.id) {
        let compensationError = null;

        try {
          await markOrderFailedAndRestoreStock(poolPromise, order.id, items);
        } catch (restoreErr) {
          compensationError = restoreErr;
          console.error('Order compensation failed:', restoreErr);
        }

        const body = {
          error: err.message,
          order_id: order.id,
          status: 'FAILED'
        };

        if (compensationError) {
          body.compensation_error = compensationError.message;
        }

        return res.status(500).json(body);
      }

      const statusCode =
        err.message.includes('Insufficient') ||
        err.message.includes('not found') ||
        err.message.includes('Invalid price')
          ? 409
          : 500;

      return res.status(statusCode).json({ error: err.message });
    } finally {
      client.release();
    }
  });

  router.get('/:id/invoice', async (req, res) => {
    try {
      if (!invoiceBucket) {
        return res.status(500).json({ error: 'INVOICE_BUCKET is not configured' });
      }

      if (!s3Client) {
        return res.status(500).json({ error: 'S3 client is not configured' });
      }

      const order = await findOrder(poolPromise, req.params.id);

      if (!order) {
        return res.status(404).json({ error: 'Order not found' });
      }

      if (String(order.status).toUpperCase() !== 'COMPLETED') {
        return res.status(409).json({ error: 'Invoice is available after order completion' });
      }

      if (!isValidInvoiceKey(order.invoice_key)) {
        return res.status(404).json({ error: 'Invoice file is not available for this order' });
      }

      const command = new GetObjectCommand({
        Bucket: invoiceBucket,
        Key: order.invoice_key,
        ResponseContentDisposition: `attachment; filename="${buildInvoiceFileName(order.id, order.invoice_key)}"`,
        ResponseContentType: 'text/plain'
      });
      const invoiceUrl = await getSignedUrlFn(s3Client, command, {
        expiresIn: INVOICE_URL_EXPIRES_IN_SECONDS
      });

      return res.json({
        order_id: order.id,
        invoice_key: order.invoice_key,
        expires_in: INVOICE_URL_EXPIRES_IN_SECONDS,
        invoice_url: invoiceUrl
      });
    } catch (err) {
      return res.status(500).json({ error: err.message });
    }
  });

  router.get('/:id', async (req, res) => {
    try {
      const order = await findOrder(poolPromise, req.params.id);

      if (!order) {
        return res.status(404).json({ error: 'Order not found' });
      }

      return res.json(withPipeline(order));
    } catch (err) {
      return res.status(500).json({ error: err.message });
    }
  });

  return router;
};
