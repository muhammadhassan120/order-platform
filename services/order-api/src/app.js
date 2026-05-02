const path = require('path');
const express = require('express');
const { Pool } = require('pg');
const { S3Client } = require('@aws-sdk/client-s3');
const { SQSClient } = require('@aws-sdk/client-sqs');
const {
  SecretsManagerClient,
  GetSecretValueCommand
} = require('@aws-sdk/client-secrets-manager');

const auth = require('./middleware/auth');
const rateLimiter = require('./middleware/rateLimiter');

const createHealthRouter = require('./routes/health');
const createOrdersRouter = require('./routes/orders');
const createInventoryRouter = require('./routes/inventory');

const app = express();
app.use(express.json());
app.use(rateLimiter);

const port = process.env.PORT || 3000;
const region = process.env.AWS_REGION || 'us-east-2';
const orderQueueUrl = process.env.ORDER_QUEUE_URL;
const dbSecretArn = process.env.DB_SECRET_ARN;
const invoiceBucket = process.env.INVOICE_BUCKET;

const secretsClient = new SecretsManagerClient({ region });
const sqsClient = new SQSClient({ region });
const s3Client = new S3Client({ region });

let pool;

async function initDB() {
  if (pool) return pool;

  if (!dbSecretArn) {
    throw new Error('DB_SECRET_ARN is not configured');
  }

  const secret = await secretsClient.send(
    new GetSecretValueCommand({ SecretId: dbSecretArn })
  );

  const creds = JSON.parse(secret.SecretString);

  pool = new Pool({
    host: creds.host,
    port: creds.port,
    database: creds.dbname,
    user: creds.username,
    password: creds.password,
    ssl: { rejectUnauthorized: false },
    max: 20
  });

  return pool;
}

const poolPromise = async () => initDB();

app.use(express.static(path.join(__dirname, '..', 'public')));
app.use('/health', createHealthRouter({ poolPromise }));
app.use('/inventory', auth, createInventoryRouter({ poolPromise }));
app.use('/orders', auth, createOrdersRouter({
  poolPromise,
  sqsClient,
  orderQueueUrl,
  s3Client,
  invoiceBucket
}));

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'index.html'));
});

app.use((req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

app.use((err, req, res, next) => {
  console.error('Unhandled app error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

if (require.main === module) {
  initDB()
    .then(() => {
      app.listen(port, () => {
        console.log(`Order API + UI running on port ${port}`);
      });
    })
    .catch((err) => {
      console.error('Failed to initialize app:', err);
      process.exit(1);
    });
}

module.exports = { app, initDB };
