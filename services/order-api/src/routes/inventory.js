const express = require('express');

module.exports = function createInventoryRouter({ poolPromise }) {
  const router = express.Router();

  router.get('/', async (req, res) => {
    try {
      const pool = await poolPromise();
      const { rows } = await pool.query(`
        SELECT id, name, price, stock, created_at
        FROM products
        ORDER BY id ASC
      `);

      res.json(rows);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  router.get('/:id', async (req, res) => {
    try {
      const pool = await poolPromise();
      const { rows } = await pool.query(
        `
        SELECT id, name, price, stock, created_at
        FROM products
        WHERE id = $1
        `,
        [req.params.id]
      );

      if (!rows.length) {
        return res.status(404).json({ error: 'Product not found' });
      }

      res.json(rows[0]);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return router;
};
