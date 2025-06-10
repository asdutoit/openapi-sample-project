const AWS = require('aws-sdk');
const {
  generateId,
  createResponse,
  createErrorResponse,
  validateApiKey,
  parsePaginationParams,
  createPaginationResponse
} = require('./common/response');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const BOOKS_TABLE = process.env.BOOKS_TABLE;
const USERS_TABLE = process.env.USERS_TABLE;
const BORROWING_TABLE = process.env.BORROWING_TABLE;

exports.listBooks = async (event) => {
  console.log('ListBooks event:', JSON.stringify(event, null, 2));

  // Validate API key
  const authResult = validateApiKey(event);
  if (!authResult.isValid) {
    return authResult.error;
  }

  try {
    const { page, limit, offset } = parsePaginationParams(event);
    const search = event.queryStringParameters?.search;
    const genre = event.queryStringParameters?.genre;
    const available = event.queryStringParameters?.available;

    let params = {
      TableName: BOOKS_TABLE,
      Limit: limit
    };

    // Build filter expression
    let filterExpressions = [];
    let expressionAttributeNames = {};
    let expressionAttributeValues = {};

    if (search) {
      filterExpressions.push('(contains(title, :search) OR contains(author, :search) OR contains(isbn, :search))');
      expressionAttributeValues[':search'] = search;
    }

    if (genre) {
      filterExpressions.push('genre = :genre');
      expressionAttributeValues[':genre'] = genre;
    }

    if (available !== undefined) {
      filterExpressions.push('available = :available');
      expressionAttributeValues[':available'] = available === 'true';
    }

    if (filterExpressions.length > 0) {
      params.FilterExpression = filterExpressions.join(' AND ');
      if (Object.keys(expressionAttributeNames).length > 0) {
        params.ExpressionAttributeNames = expressionAttributeNames;
      }
      if (Object.keys(expressionAttributeValues).length > 0) {
        params.ExpressionAttributeValues = expressionAttributeValues;
      }
    }

    const result = await dynamodb.scan(params).promise();
    
    // Format books according to OpenAPI spec
    const books = result.Items.map(book => ({
      id: book.id,
      isbn: book.isbn,
      title: book.title,
      author: book.author,
      genre: book.genre,
      publicationYear: book.publicationYear,
      publisher: book.publisher,
      available: book.availableCopies > 0,
      totalCopies: book.totalCopies,
      availableCopies: book.availableCopies
    }));

    // Create paginated response
    const response = createPaginationResponse(
      books,
      result.Count || 0,
      page,
      limit
    );

    return createResponse(200, { books: response.items, pagination: response.pagination });

  } catch (error) {
    console.error('Error listing books:', error);
    return createErrorResponse(500, 'INTERNAL_SERVER_ERROR', 'An unexpected error occurred');
  }
};

exports.createBook = async (event) => {
  console.log('CreateBook event:', JSON.stringify(event, null, 2));

  // Validate API key
  const authResult = validateApiKey(event);
  if (!authResult.isValid) {
    return authResult.error;
  }

  try {
    const body = JSON.parse(event.body);
    
    // Validate required fields
    const requiredFields = ['isbn', 'title', 'author', 'genre', 'publicationYear', 'totalCopies'];
    const missingFields = requiredFields.filter(field => !body[field]);
    
    if (missingFields.length > 0) {
      return createErrorResponse(
        400, 
        'BAD_REQUEST', 
        'Invalid request parameters',
        { missing_fields: missingFields }
      );
    }

    // Validate ISBN format
    const isbnRegex = /^978-[0-9]{1}-[0-9]{4}-[0-9]{4}-[0-9]{1}$/;
    if (!isbnRegex.test(body.isbn)) {
      return createErrorResponse(
        400,
        'BAD_REQUEST',
        'Invalid request parameters',
        { field: 'isbn', reason: 'Invalid ISBN format' }
      );
    }

    // Validate genre
    const validGenres = ['fiction', 'non-fiction', 'science', 'history', 'biography', 'children'];
    if (!validGenres.includes(body.genre)) {
      return createErrorResponse(
        400,
        'BAD_REQUEST',
        'Invalid request parameters',
        { field: 'genre', reason: 'Invalid genre' }
      );
    }

    // Check if book already exists
    const existingBook = await dynamodb.query({
      TableName: BOOKS_TABLE,
      IndexName: 'ISBNIndex',
      KeyConditionExpression: 'isbn = :isbn',
      ExpressionAttributeValues: { ':isbn': body.isbn }
    }).promise();

    if (existingBook.Items && existingBook.Items.length > 0) {
      return createErrorResponse(409, 'CONFLICT', 'A book with this ISBN already exists');
    }

    // Create new book
    const timestamp = new Date().toISOString();
    const newBook = {
      id: generateId('bk'),
      isbn: body.isbn,
      title: body.title,
      author: body.author,
      genre: body.genre,
      publicationYear: body.publicationYear,
      publisher: body.publisher || null,
      totalCopies: body.totalCopies,
      availableCopies: body.totalCopies,
      createdAt: timestamp,
      updatedAt: timestamp
    };

    await dynamodb.put({
      TableName: BOOKS_TABLE,
      Item: newBook
    }).promise();

    // Format response
    const response = {
      id: newBook.id,
      isbn: newBook.isbn,
      title: newBook.title,
      author: newBook.author,
      genre: newBook.genre,
      publicationYear: newBook.publicationYear,
      publisher: newBook.publisher,
      available: true,
      totalCopies: newBook.totalCopies,
      availableCopies: newBook.availableCopies
    };

    return createResponse(201, response);

  } catch (error) {
    console.error('Error creating book:', error);
    return createErrorResponse(500, 'INTERNAL_SERVER_ERROR', 'An unexpected error occurred');
  }
};

exports.borrowBook = async (event) => {
  console.log('BorrowBook event:', JSON.stringify(event, null, 2));

  // Validate API key
  const authResult = validateApiKey(event);
  if (!authResult.isValid) {
    return authResult.error;
  }

  const transactItems = [];

  try {
    const bookId = event.pathParameters.bookId;
    const body = JSON.parse(event.body);
    
    // Validate book ID format
    if (!bookId || !bookId.match(/^bk_[a-zA-Z0-9]{6}$/)) {
      return createErrorResponse(
        400,
        'BAD_REQUEST',
        'Invalid request parameters',
        { field: 'bookId', reason: 'Invalid book ID format' }
      );
    }

    // Validate user ID format
    if (!body.userId || !body.userId.match(/^usr_[a-zA-Z0-9]{6}$/)) {
      return createErrorResponse(
        400,
        'BAD_REQUEST',
        'Invalid request parameters',
        { field: 'userId', reason: 'Invalid user ID format' }
      );
    }

    const durationDays = body.durationDays || 14;

    // Get book details
    const bookResult = await dynamodb.get({
      TableName: BOOKS_TABLE,
      Key: { id: bookId }
    }).promise();

    if (!bookResult.Item) {
      return createErrorResponse(404, 'NOT_FOUND', 'The requested resource was not found');
    }

    const book = bookResult.Item;

    // Check if book is available
    if (book.availableCopies <= 0) {
      return createErrorResponse(409, 'CONFLICT', 'This book is not available for borrowing');
    }

    // Get user details
    const userResult = await dynamodb.get({
      TableName: USERS_TABLE,
      Key: { id: body.userId }
    }).promise();

    if (!userResult.Item) {
      return createErrorResponse(404, 'NOT_FOUND', 'The requested resource was not found');
    }

    const user = userResult.Item;

    // Check if user has reached borrowing limit
    if (user.currentBorrowedCount >= user.borrowingLimit) {
      return createErrorResponse(409, 'CONFLICT', 'User has reached borrowing limit');
    }

    // Create borrowing record
    const timestamp = new Date();
    const dueDate = new Date(timestamp);
    dueDate.setDate(dueDate.getDate() + durationDays);

    const borrowingRecord = {
      id: generateId('brw'),
      userId: body.userId,
      bookId: bookId,
      bookTitle: book.title,
      borrowedAt: timestamp.toISOString(),
      dueDate: dueDate.toISOString(),
      status: 'active',
      createdAt: timestamp.toISOString()
    };

    // Use transaction to ensure consistency
    await dynamodb.transactWrite({
      TransactItems: [
        {
          Put: {
            TableName: BORROWING_TABLE,
            Item: borrowingRecord
          }
        },
        {
          Update: {
            TableName: BOOKS_TABLE,
            Key: { id: bookId },
            UpdateExpression: 'SET availableCopies = availableCopies - :dec, updatedAt = :timestamp',
            ConditionExpression: 'availableCopies > :zero',
            ExpressionAttributeValues: {
              ':dec': 1,
              ':zero': 0,
              ':timestamp': timestamp.toISOString()
            }
          }
        },
        {
          Update: {
            TableName: USERS_TABLE,
            Key: { id: body.userId },
            UpdateExpression: 'SET currentBorrowedCount = currentBorrowedCount + :inc, updatedAt = :timestamp',
            ExpressionAttributeValues: {
              ':inc': 1,
              ':timestamp': timestamp.toISOString()
            }
          }
        }
      ]
    }).promise();

    // Format response
    const response = {
      id: borrowingRecord.id,
      userId: borrowingRecord.userId,
      bookId: borrowingRecord.bookId,
      borrowedAt: borrowingRecord.borrowedAt,
      dueDate: borrowingRecord.dueDate,
      status: borrowingRecord.status
    };

    return createResponse(200, response);

  } catch (error) {
    console.error('Error borrowing book:', error);
    
    if (error.code === 'TransactionCanceledException') {
      return createErrorResponse(409, 'CONFLICT', 'Unable to borrow book - please try again');
    }
    
    return createErrorResponse(500, 'INTERNAL_SERVER_ERROR', 'An unexpected error occurred');
  }
};

exports.returnBook = async (event) => {
  console.log('ReturnBook event:', JSON.stringify(event, null, 2));

  // Validate API key
  const authResult = validateApiKey(event);
  if (!authResult.isValid) {
    return authResult.error;
  }

  try {
    const bookId = event.pathParameters.bookId;
    const body = JSON.parse(event.body);
    
    // Validate book ID format
    if (!bookId || !bookId.match(/^bk_[a-zA-Z0-9]{6}$/)) {
      return createErrorResponse(
        400,
        'BAD_REQUEST',
        'Invalid request parameters',
        { field: 'bookId', reason: 'Invalid book ID format' }
      );
    }

    // Validate user ID format
    if (!body.userId || !body.userId.match(/^usr_[a-zA-Z0-9]{6}$/)) {
      return createErrorResponse(
        400,
        'BAD_REQUEST',
        'Invalid request parameters',
        { field: 'userId', reason: 'Invalid user ID format' }
      );
    }

    // Find active borrowing record
    const borrowingResult = await dynamodb.query({
      TableName: BORROWING_TABLE,
      IndexName: 'UserIndex',
      KeyConditionExpression: 'userId = :userId AND #status = :status',
      FilterExpression: 'bookId = :bookId',
      ExpressionAttributeNames: { '#status': 'status' },
      ExpressionAttributeValues: {
        ':userId': body.userId,
        ':bookId': bookId,
        ':status': 'active'
      }
    }).promise();

    if (!borrowingResult.Items || borrowingResult.Items.length === 0) {
      return createErrorResponse(404, 'NOT_FOUND', 'No active borrowing record found');
    }

    const borrowingRecord = borrowingResult.Items[0];
    const timestamp = new Date().toISOString();

    // Use transaction to ensure consistency
    await dynamodb.transactWrite({
      TransactItems: [
        {
          Update: {
            TableName: BORROWING_TABLE,
            Key: { id: borrowingRecord.id },
            UpdateExpression: 'SET #status = :status, returnedAt = :timestamp, updatedAt = :timestamp',
            ExpressionAttributeNames: { '#status': 'status' },
            ExpressionAttributeValues: {
              ':status': 'returned',
              ':timestamp': timestamp
            }
          }
        },
        {
          Update: {
            TableName: BOOKS_TABLE,
            Key: { id: bookId },
            UpdateExpression: 'SET availableCopies = availableCopies + :inc, updatedAt = :timestamp',
            ExpressionAttributeValues: {
              ':inc': 1,
              ':timestamp': timestamp
            }
          }
        },
        {
          Update: {
            TableName: USERS_TABLE,
            Key: { id: body.userId },
            UpdateExpression: 'SET currentBorrowedCount = currentBorrowedCount - :dec, updatedAt = :timestamp',
            ConditionExpression: 'currentBorrowedCount > :zero',
            ExpressionAttributeValues: {
              ':dec': 1,
              ':zero': 0,
              ':timestamp': timestamp
            }
          }
        }
      ]
    }).promise();

    // Format response
    const response = {
      id: borrowingRecord.id,
      userId: borrowingRecord.userId,
      bookId: borrowingRecord.bookId,
      borrowedAt: borrowingRecord.borrowedAt,
      dueDate: borrowingRecord.dueDate,
      returnedAt: timestamp,
      status: 'returned'
    };

    return createResponse(200, response);

  } catch (error) {
    console.error('Error returning book:', error);
    
    if (error.code === 'TransactionCanceledException') {
      return createErrorResponse(409, 'CONFLICT', 'Unable to return book - please try again');
    }
    
    return createErrorResponse(500, 'INTERNAL_SERVER_ERROR', 'An unexpected error occurred');
  }
};