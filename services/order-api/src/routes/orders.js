const express = require('express');
const { SendMessageCommand } = require('@aws-sdk/client-sqs');

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

      return res.status(201).json({
        order_id: order.id,
        status: 'PENDING',
        total: order.total
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

      return res.json(rows[0]);
    } catch (err) {
      return res.status(500).json({ error: err.message });
    }
  });

  return router;
};
