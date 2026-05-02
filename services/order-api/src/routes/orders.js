const express = require('express');
const { SendMessageCommand } = require('@aws-sdk/client-sqs');

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

module.exports = function createOrdersRouter({ poolPromise, sqsClient, orderQueueUrl }) {
  const router = express.Router();

  router.post('/', async (req, res) => {
    const { customer_email, items } = req.body;

    if (!customer_email || !items?.length) {
      return res.status(400).json({
        error: 'customer_email and items[] required'
      });
    }

    const pool = await poolPromise();
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      let total = 0;

      for (const item of items) {
        const qty = Number(item.qty);

        if (!item.product_id || !qty || qty <= 0) {
          throw new Error('Each item must contain product_id and qty > 0');
        }

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

        if (rows[0].stock < qty) {
          throw new Error(`Insufficient stock for ${item.product_id}`);
        }

        total += Number(rows[0].price) * qty;

        await client.query(
          `
          UPDATE products
          SET stock = stock - $1
          WHERE id = $2
          `,
          [qty, item.product_id]
        );
      }

      const { rows: [order] } = await client.query(
        `
        INSERT INTO orders (customer_email, items, total, status, created_at)
        VALUES ($1, $2, $3, 'PENDING', NOW())
        RETURNING id, status, total, created_at
        `,
        [customer_email, JSON.stringify(items), total]
      );

      await client.query('COMMIT');

      if (!orderQueueUrl) {
        throw new Error('ORDER_QUEUE_URL is not configured');
      }

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
      try {
        await client.query('ROLLBACK');
      } catch (_) {}

      console.error('Order creation failed:', err);

      const statusCode =
        err.message.includes('Insufficient') ||
        err.message.includes('not found') ||
        err.message.includes('Each item')
          ? 409
          : 500;

      return res.status(statusCode).json({ error: err.message });
    } finally {
      client.release();
    }
  });

  router.get('/:id', async (req, res) => {
    try {
      const pool = await poolPromise();
      const { rows } = await pool.query(
        `
        SELECT id, customer_email, items, total, status, created_at, processed_at, payment_ref, invoice_key
        FROM orders
        WHERE id = $1
        `,
        [req.params.id]
      );

      if (!rows.length) {
        return res.status(404).json({ error: 'Order not found' });
      }

      return res.json(withPipeline(rows[0]));
    } catch (err) {
      return res.status(500).json({ error: err.message });
    }
  });

  return router;
};
