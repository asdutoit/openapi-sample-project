const AWS = require('aws-sdk');
const bcrypt = require('bcryptjs');
const {
  generateId,
  createResponse,
  createErrorResponse,
  validateApiKey,
  parsePaginationParams,
  createPaginationResponse
} = require('./common/response');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const USERS_TABLE = process.env.USERS_TABLE;
const BORROWING_TABLE = process.env.BORROWING_TABLE;

exports.listUsers = async (event) => {
  console.log('ListUsers event:', JSON.stringify(event, null, 2));

  // Validate API key
  const authResult = validateApiKey(event);
  if (!authResult.isValid) {
    return authResult.error;
  }

  try {
    const { page, limit, offset } = parsePaginationParams(event);
    const search = event.queryStringParameters?.search;

    let params = {
      TableName: USERS_TABLE,
      Limit: limit
    };

    // For search functionality, we'd need to implement a GSI or use a search service
    // For now, we'll do a simple scan with filter
    if (search) {
      params.FilterExpression = 'contains(#name, :search) OR contains(email, :search)';
      params.ExpressionAttributeNames = { '#name': 'name' };
      params.ExpressionAttributeValues = { ':search': search };
    }

    const result = await dynamodb.scan(params).promise();
    
    // Format users according to OpenAPI spec
    const users = result.Items.map(user => ({
      id: user.id,
      email: user.email,
      name: user.name,
      membershipStatus: user.membershipStatus || 'active',
      borrowingLimit: user.borrowingLimit || 5,
      currentBorrowedCount: user.currentBorrowedCount || 0,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt
    }));

    // Create paginated response
    const response = createPaginationResponse(
      users,
      result.Count || 0,
      page,
      limit
    );

    return createResponse(200, { users: response.items, pagination: response.pagination });

  } catch (error) {
    console.error('Error listing users:', error);
    return createErrorResponse(500, 'INTERNAL_SERVER_ERROR', 'An unexpected error occurred');
  }
};

exports.createUser = async (event) => {
  console.log('CreateUser event:', JSON.stringify(event, null, 2));

  // Validate API key
  const authResult = validateApiKey(event);
  if (!authResult.isValid) {
    return authResult.error;
  }

  try {
    const body = JSON.parse(event.body);
    
    // Validate required fields
    if (!body.email || !body.name || !body.password) {
      return createErrorResponse(
        400, 
        'BAD_REQUEST', 
        'Invalid request parameters',
        { missing_fields: ['email', 'name', 'password'].filter(field => !body[field]) }
      );
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(body.email)) {
      return createErrorResponse(
        400,
        'BAD_REQUEST',
        'Invalid request parameters',
        { field: 'email', reason: 'Invalid email format' }
      );
    }

    // Check if user already exists
    const existingUser = await dynamodb.query({
      TableName: USERS_TABLE,
      IndexName: 'EmailIndex',
      KeyConditionExpression: 'email = :email',
      ExpressionAttributeValues: { ':email': body.email }
    }).promise();

    if (existingUser.Items && existingUser.Items.length > 0) {
      return createErrorResponse(409, 'CONFLICT', 'A user with this email already exists');
    }

    // Hash password
    const hashedPassword = await bcrypt.hash(body.password, 10);

    // Create new user
    const timestamp = new Date().toISOString();
    const newUser = {
      id: generateId('usr'),
      email: body.email,
      name: body.name,
      passwordHash: hashedPassword,
      phoneNumber: body.phoneNumber || null,
      membershipStatus: 'active',
      borrowingLimit: 5,
      currentBorrowedCount: 0,
      createdAt: timestamp,
      updatedAt: timestamp
    };

    await dynamodb.put({
      TableName: USERS_TABLE,
      Item: newUser
    }).promise();

    // Return user without password hash
    const { passwordHash, ...userResponse } = newUser;
    return createResponse(201, userResponse);

  } catch (error) {
    console.error('Error creating user:', error);
    return createErrorResponse(500, 'INTERNAL_SERVER_ERROR', 'An unexpected error occurred');
  }
};

exports.getUser = async (event) => {
  console.log('GetUser event:', JSON.stringify(event, null, 2));

  // Validate API key
  const authResult = validateApiKey(event);
  if (!authResult.isValid) {
    return authResult.error;
  }

  try {
    const userId = event.pathParameters.userId;

    // Validate userId format
    if (!userId || !userId.match(/^usr_[a-zA-Z0-9]{6}$/)) {
      return createErrorResponse(
        400,
        'BAD_REQUEST',
        'Invalid request parameters',
        { field: 'userId', reason: 'Invalid user ID format' }
      );
    }

    // Get user details
    const userResult = await dynamodb.get({
      TableName: USERS_TABLE,
      Key: { id: userId }
    }).promise();

    if (!userResult.Item) {
      return createErrorResponse(404, 'NOT_FOUND', 'The requested resource was not found');
    }

    const user = userResult.Item;

    // Get borrowed books
    const borrowingResult = await dynamodb.query({
      TableName: BORROWING_TABLE,
      IndexName: 'UserIndex',
      KeyConditionExpression: 'userId = :userId AND #status = :status',
      ExpressionAttributeNames: { '#status': 'status' },
      ExpressionAttributeValues: {
        ':userId': userId,
        ':status': 'active'
      }
    }).promise();

    const borrowedBooks = borrowingResult.Items.map(record => ({
      bookId: record.bookId,
      title: record.bookTitle || 'Unknown Title', // In real implementation, would join with books table
      borrowedAt: record.borrowedAt,
      dueDate: record.dueDate
    }));

    // Format response according to OpenAPI spec
    const response = {
      id: user.id,
      email: user.email,
      name: user.name,
      phoneNumber: user.phoneNumber,
      membershipStatus: user.membershipStatus,
      borrowingLimit: user.borrowingLimit,
      currentBorrowedCount: user.currentBorrowedCount,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      borrowedBooks
    };

    return createResponse(200, response);

  } catch (error) {
    console.error('Error getting user:', error);
    return createErrorResponse(500, 'INTERNAL_SERVER_ERROR', 'An unexpected error occurred');
  }
};