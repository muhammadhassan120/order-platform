const express = require('express');
const request = require('supertest');

const createOrdersRouter = require('../src/routes/orders');

function buildApp(router) {
  const app = express();
  app.use(express.json());
  app.use('/orders', router);
  return app;
}

describe('orders route', () => {
  function completedOrder(overrides = {}) {
    return {
      id: 42,
      customer_email: 'customer@example.com',
      items: [{ product_id: 'SMOKE-001', qty: 1 }],
      total: '0.01',
      status: 'COMPLETED',
      created_at: new Date('2026-05-02T06:00:00.000Z'),
      processed_at: new Date('2026-05-02T06:00:04.250Z'),
      payment_ref: 'PAY-42',
      invoice_key: 'invoices/42/PAY-42.txt',
      ...overrides
    };
  }

  test('GET /orders/:id returns live pipeline metadata', async () => {
    const pool = {
      query: jest.fn().mockResolvedValue({
        rows: [completedOrder()]
      })
    };

    const app = buildApp(createOrdersRouter({
      poolPromise: async () => pool,
      sqsClient: { send: jest.fn() },
      orderQueueUrl: 'queue-url'
    }));

    const response = await request(app).get('/orders/42');

    expect(response.status).toBe(200);
    expect(response.body.pipeline).toMatchObject({
      status: 'COMPLETED',
      percent: 100,
      terminal: true,
      processing_duration_ms: 4250
    });
    expect(response.body.pipeline.stages.map((stage) => stage.key)).toEqual([
      'api',
      'rds',
      'sqs',
      'lambda',
      'artifacts'
    ]);
  });

  test('GET /orders/:id/invoice returns a pre-signed invoice URL for completed orders', async () => {
    const pool = {
      query: jest.fn().mockResolvedValue({
        rows: [completedOrder()]
      })
    };
    const getSignedUrlFn = jest.fn().mockResolvedValue('https://signed.example/invoice.txt');
    const app = buildApp(createOrdersRouter({
      poolPromise: async () => pool,
      sqsClient: { send: jest.fn() },
      orderQueueUrl: 'queue-url',
      s3Client: {},
      invoiceBucket: 'order-platform-invoices',
      getSignedUrlFn
    }));

    const response = await request(app).get('/orders/42/invoice');

    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({
      order_id: 42,
      invoice_key: 'invoices/42/PAY-42.txt',
      expires_in: 300,
      invoice_url: 'https://signed.example/invoice.txt'
    });
    expect(getSignedUrlFn).toHaveBeenCalledWith(
      {},
      expect.objectContaining({
        input: expect.objectContaining({
          Bucket: 'order-platform-invoices',
          Key: 'invoices/42/PAY-42.txt',
          ResponseContentDisposition: 'attachment; filename="order-42-invoice.txt"'
        })
      }),
      { expiresIn: 300 }
    );
  });

  test('GET /orders/:id/invoice blocks invoices until processing is complete', async () => {
    const pool = {
      query: jest.fn().mockResolvedValue({
        rows: [completedOrder({ status: 'PROCESSING', processed_at: null, invoice_key: null })]
      })
    };
    const app = buildApp(createOrdersRouter({
      poolPromise: async () => pool,
      sqsClient: { send: jest.fn() },
      orderQueueUrl: 'queue-url',
      s3Client: {},
      invoiceBucket: 'order-platform-invoices'
    }));

    const response = await request(app).get('/orders/42/invoice');

    expect(response.status).toBe(409);
    expect(response.body.error).toBe('Invoice is available after order completion');
  });

  test('POST /orders returns queue timing and pending pipeline metadata', async () => {
    const client = {
      query: jest.fn(async (sql) => {
        if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') {
          return {};
        }

        if (sql.includes('SELECT id, price, stock')) {
          return {
            rows: [
              {
                id: 'SMOKE-001',
                price: '0.01',
                stock: 10
              }
            ]
          };
        }

        if (sql.includes('INSERT INTO orders')) {
          return {
            rows: [
              {
                id: 7,
                status: 'PENDING',
                total: '0.01',
                created_at: new Date('2026-05-02T06:00:00.000Z')
              }
            ]
          };
        }

        return {};
      }),
      release: jest.fn()
    };

    const pool = {
      connect: jest.fn().mockResolvedValue(client)
    };
    const sqsClient = { send: jest.fn().mockResolvedValue({}) };
    const app = buildApp(createOrdersRouter({
      poolPromise: async () => pool,
      sqsClient,
      orderQueueUrl: 'queue-url'
    }));

    const response = await request(app)
      .post('/orders')
      .send({
        customer_email: 'customer@example.com',
        items: [{ product_id: 'SMOKE-001', qty: 1 }]
      });

    expect(response.status).toBe(201);
    expect(response.body).toMatchObject({
      order_id: 7,
      status: 'PENDING',
      total: '0.01'
    });
    expect(response.body.created_at).toBeTruthy();
    expect(response.body.queued_at).toBeTruthy();
    expect(response.body.pipeline.status).toBe('PENDING');
    expect(response.body.pipeline.percent).toBeGreaterThan(0);
    expect(sqsClient.send).toHaveBeenCalledTimes(1);
  });
});
