module.exports = function auth(req, res, next) {
  const authEnabled = process.env.AUTH_ENABLED === 'true';

  if (!authEnabled) {
    return next();
  }

  const apiKey = req.header('x-api-key');
  const expectedApiKey = process.env.API_KEY;

  if (!expectedApiKey) {
    return res.status(500).json({ error: 'API_KEY is not configured on server' });
  }

  if (!apiKey || apiKey !== expectedApiKey) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  next();
};
