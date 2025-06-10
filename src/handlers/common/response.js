const crypto = require('crypto');

const corsHeaders = {
  'Access-Control-Allow-Origin': process.env.ALLOWED_ORIGINS || '*',
  'Access-Control-Allow-Headers': 'Content-Type,X-API-Key,Authorization',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
};

const rateLimitHeaders = {
  'X-RateLimit-Limit': process.env.RATE_LIMIT_PER_MINUTE || '100',
  'X-RateLimit-Remaining': '95', // This would be calculated based on actual usage
  'X-RateLimit-Reset': Math.floor(Date.now() / 1000) + 3600
};

function generateId(prefix) {
  return `${prefix}_${crypto.randomBytes(3).toString('hex')}`;
}

function createResponse(statusCode, body, additionalHeaders = {}) {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      ...corsHeaders,
      ...rateLimitHeaders,
      ...additionalHeaders
    },
    body: JSON.stringify(body)
  };
}

function createErrorResponse(statusCode, errorCode, message, details = null) {
  const errorBody = {
    error: errorCode,
    message,
    timestamp: new Date().toISOString()
  };

  if (details) {
    errorBody.details = details;
  }

  return createResponse(statusCode, errorBody);
}

function validateApiKey(event) {
  const apiKey = event.headers['X-API-Key'] || event.headers['x-api-key'];
  
  if (!apiKey) {
    return {
      isValid: false,
      error: createErrorResponse(401, 'UNAUTHORIZED', 'Missing or invalid API key')
    };
  }

  // In a real implementation, this would validate against stored API keys
  // For now, we'll do a simple check
  const validApiKey = process.env.API_KEY_VALUE || 'test-api-key';
  
  if (apiKey !== validApiKey) {
    return {
      isValid: false,
      error: createErrorResponse(401, 'UNAUTHORIZED', 'Missing or invalid API key')
    };
  }

  return { isValid: true };
}

function parsePaginationParams(event) {
  const page = parseInt(event.queryStringParameters?.page || '1', 10);
  const limit = parseInt(event.queryStringParameters?.limit || '20', 10);

  // Validate pagination parameters
  const validPage = Math.max(1, page);
  const validLimit = Math.max(1, Math.min(100, limit));

  return {
    page: validPage,
    limit: validLimit,
    offset: (validPage - 1) * validLimit
  };
}

function createPaginationResponse(items, totalItems, page, limit) {
  const totalPages = Math.ceil(totalItems / limit);
  
  return {
    items,
    pagination: {
      page,
      limit,
      totalPages,
      totalItems
    }
  };
}

module.exports = {
  generateId,
  createResponse,
  createErrorResponse,
  validateApiKey,
  parsePaginationParams,
  createPaginationResponse,
  corsHeaders,
  rateLimitHeaders
};