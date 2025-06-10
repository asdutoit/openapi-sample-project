# Book Library Management API Documentation

## Overview

The Book Library Management API is a comprehensive RESTful API built using an OpenAPI-first approach. It provides functionality for managing a digital library system including user management, book inventory, and borrowing/returning operations.

## API Documentation

The live API documentation is available at:
- **Development**: https://api-dev.booklibrary.com/docs
- **Staging**: https://api-staging.booklibrary.com/docs  
- **Production**: https://api.booklibrary.com/docs

## Quick Start

### Authentication

All API endpoints require authentication using an API key. Include the API key in the request header:

```http
X-API-Key: your-api-key-here
```

### Base URLs

- **Development**: `https://api-dev.booklibrary.com`
- **Staging**: `https://api-staging.booklibrary.com`
- **Production**: `https://api.booklibrary.com`

### Example Requests

#### List Users

```bash
curl -X GET "https://api.booklibrary.com/users?page=1&limit=10" \
  -H "X-API-Key: your-api-key" \
  -H "Accept: application/json"
```

#### Create a New User

```bash
curl -X POST "https://api.booklibrary.com/users" \
  -H "X-API-Key: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "name": "John Doe",
    "password": "SecurePass123!"
  }'
```

#### List Books

```bash
curl -X GET "https://api.booklibrary.com/books?genre=fiction&available=true" \
  -H "X-API-Key: your-api-key" \
  -H "Accept: application/json"
```

#### Borrow a Book

```bash
curl -X POST "https://api.booklibrary.com/books/bk_123456/borrow" \
  -H "X-API-Key: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "usr_789012",
    "durationDays": 14
  }'
```

## API Endpoints

### Users

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/users` | List all users with pagination |
| POST | `/users` | Create a new user |
| GET | `/users/{userId}` | Get user details by ID |

### Books

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/books` | List all books with filtering |
| POST | `/books` | Add a new book to inventory |

### Borrowing

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/books/{bookId}/borrow` | Borrow a book |
| POST | `/books/{bookId}/return` | Return a borrowed book |

## Response Format

All API responses follow a consistent format:

### Success Response

```json
{
  "data": {
    // Response data here
  },
  "pagination": {
    "page": 1,
    "limit": 20,
    "totalPages": 5,
    "totalItems": 98
  }
}
```

### Error Response

```json
{
  "error": "ERROR_CODE",
  "message": "Human-readable error message",
  "timestamp": "2023-11-21T15:30:00Z",
  "details": {
    // Additional error details if available
  }
}
```

## Status Codes

| Code | Description |
|------|-------------|
| 200 | Success |
| 201 | Created |
| 400 | Bad Request |
| 401 | Unauthorized |
| 404 | Not Found |
| 409 | Conflict |
| 429 | Rate Limit Exceeded |
| 500 | Internal Server Error |

## Rate Limiting

The API implements rate limiting to ensure fair usage:

- **Development**: 100 requests per minute
- **Staging**: 200 requests per minute
- **Production**: 1000 requests per minute

Rate limit headers are included in all responses:

```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 995
X-RateLimit-Reset: 1700593200
```

## Pagination

List endpoints support pagination using query parameters:

- `page`: Page number (default: 1)
- `limit`: Items per page (default: 20, max: 100)

Example:
```
GET /users?page=2&limit=50
```

## Filtering and Search

### Users
- `search`: Search by name or email

### Books
- `search`: Search by title, author, or ISBN
- `genre`: Filter by genre (fiction, non-fiction, science, history, biography, children)
- `available`: Filter by availability (true/false)

## Data Models

### User

```json
{
  "id": "usr_123456",
  "email": "user@example.com",
  "name": "John Doe",
  "membershipStatus": "active",
  "borrowingLimit": 5,
  "currentBorrowedCount": 2,
  "createdAt": "2023-01-15T10:30:00Z",
  "updatedAt": "2023-11-20T14:22:00Z"
}
```

### Book

```json
{
  "id": "bk_987654",
  "isbn": "978-0-7432-7356-5",
  "title": "The Great Gatsby",
  "author": "F. Scott Fitzgerald",
  "genre": "fiction",
  "publicationYear": 1925,
  "available": true,
  "totalCopies": 5,
  "availableCopies": 3
}
```

### Borrowing Record

```json
{
  "id": "brw_789456",
  "userId": "usr_123456",
  "bookId": "bk_987654",
  "borrowedAt": "2023-11-21T16:00:00Z",
  "dueDate": "2023-12-05T16:00:00Z",
  "status": "active"
}
```

## Error Handling

The API provides detailed error messages to help with troubleshooting:

### Validation Errors

```json
{
  "error": "BAD_REQUEST",
  "message": "Invalid request parameters",
  "timestamp": "2023-11-21T15:30:00Z",
  "details": {
    "field": "email",
    "reason": "Invalid email format"
  }
}
```

### Business Logic Errors

```json
{
  "error": "CONFLICT",
  "message": "User has reached borrowing limit",
  "timestamp": "2023-11-21T15:30:00Z"
}
```

## Security

- All endpoints require API key authentication
- HTTPS is enforced for all communications
- Input validation is performed on all requests
- Rate limiting prevents abuse
- AWS WAF protection in staging and production environments

## SDKs and Libraries

### JavaScript/Node.js

```bash
npm install @booklibrary/api-client
```

### Python

```bash
pip install booklibrary-api-client
```

### cURL Examples

See the examples above for common cURL usage patterns.

## Support

For API support and questions:

- **Email**: api-support@booklibrary.com
- **Documentation**: https://docs.booklibrary.com
- **Status Page**: https://status.booklibrary.com

## Changelog

### v1.0.0 (2023-11-21)
- Initial release
- User management endpoints
- Book inventory management
- Borrowing and returning functionality
- Rate limiting and authentication
- Comprehensive error handling