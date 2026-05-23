const express = require('express');
const request = require('supertest');

const createHealthRouter = require('../src/routes/health');

function buildApp(router) {
  const app = express();
  app.use('/health', router);
  return app;
}

describe('health route', () => {
  test('GET /health returns healthy when the database responds', async () => {
    const pool = {
      query: jest.fn().mockResolvedValue({})
    };
    const app = buildApp(createHealthRouter({ poolPromise: async () => pool }));

    const response = await request(app).get('/health');

    expect(response.status).toBe(200);
    expect(response.body.status).toBe('healthy');
    expect(response.body.timestamp).toBeTruthy();
    expect(pool.query).toHaveBeenCalledWith('SELECT 1');
  });

  test('GET /health returns 503 when the database fails', async () => {
    const pool = {
      query: jest.fn().mockRejectedValue(new Error('db down'))
    };
    const app = buildApp(createHealthRouter({ poolPromise: async () => pool }));

    const response = await request(app).get('/health');

    expect(response.status).toBe(503);
    expect(response.body).toEqual({
      status: 'unhealthy',
      error: 'db down'
    });
  });
});
