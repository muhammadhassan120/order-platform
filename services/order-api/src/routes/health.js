const express = require('express');

module.exports = function createHealthRouter({ poolPromise }) {
  const router = express.Router();

  router.get('/', async (req, res) => {
    try {
      const pool = await poolPromise();
      await pool.query('SELECT 1');
      res.json({
        status: 'healthy',
        timestamp: new Date().toISOString()
      });
    } catch (err) {
      res.status(503).json({
        status: 'unhealthy',
        error: err.message
      });
    }
  });

  return router;
};
