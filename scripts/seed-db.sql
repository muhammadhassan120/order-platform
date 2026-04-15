CREATE TABLE IF NOT EXISTS products (
  id         VARCHAR(50) PRIMARY KEY,
  name       VARCHAR(255) NOT NULL,
  price      NUMERIC(10,2) NOT NULL,
  stock      INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS orders (
  id             SERIAL PRIMARY KEY,
  customer_email VARCHAR(255) NOT NULL,
  items          JSONB NOT NULL,
  total          NUMERIC(10,2) NOT NULL,
  status         VARCHAR(20) NOT NULL DEFAULT 'PENDING',
  payment_ref    VARCHAR(50),
  invoice_key    VARCHAR(255),
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  processed_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_orders_status
  ON orders(status);

CREATE INDEX IF NOT EXISTS idx_orders_customer_email
  ON orders(customer_email);

CREATE INDEX IF NOT EXISTS idx_orders_created_at
  ON orders(created_at DESC);

INSERT INTO products (id, name, price, stock)
VALUES
  ('PROD-001', 'Wireless Keyboard', 49.99, 500),
  ('PROD-002', 'USB-C Hub', 34.99, 300),
  ('PROD-003', 'Monitor Stand', 79.99, 150),
  ('PROD-004', 'Noise-Cancelling Mic', 129.99, 200),
  ('SMOKE-001', 'Smoke Test Product', 0.01, 999999)
ON CONFLICT (id) DO NOTHING;
