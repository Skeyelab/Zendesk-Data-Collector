# Zendesk Proxy Webhook API Documentation

## Overview

The Zendesk Proxy Webhook allows external systems (like n8n) to interact with Zendesk resources (tickets, users, etc.) through this application's rate-limited queue. This ensures that all Zendesk API calls are properly rate-limited and don't interfere with background sync operations.

## Authentication

All requests must include an `X-Webhook-Secret` header with the secret configured in the `WEBHOOKS_ZENDESK_SECRET` environment variable.

```bash
X-Webhook-Secret: your_secret_here
```

**Migration Note**: The webhook secret was renamed from `WEBHOOKS_TICKETS_SECRET` to `WEBHOOKS_ZENDESK_SECRET` to reflect the unified nature of the endpoint. For backwards compatibility, the system will fall back to `WEBHOOKS_TICKETS_SECRET` if `WEBHOOKS_ZENDESK_SECRET` is not set, but it's recommended to migrate to the new variable name.

## Endpoint

```
POST /webhooks/zendesk
```

**Migration Note**: The previous endpoint `POST /webhooks/tickets` has been replaced with the unified `/webhooks/zendesk` endpoint. All integrations must be updated to use the new endpoint and include the `resource` parameter.

## Request Format

All requests must be sent as JSON with the following structure:

```json
{
  "domain": "your-subdomain.zendesk.com",
  "resource": "tickets|users",
  "method": "get|put|post|patch|delete",
  "ticket_id": 12345,
  "body": {
    "ticket": {
      "subject": "Ticket subject",
      "priority": "high",
      "status": "open"
    }
  }
}
```

### Common Parameters

- **domain** (required): Your Zendesk domain (e.g., "support.example.com")
- **resource** (required): The Zendesk resource type to interact with:
  - `tickets`: Zendesk Tickets API
  - `users`: Zendesk Users API
- **method** (optional): HTTP method to use. Default: "get"
  - `get`: Retrieve resource information (synchronous)
  - `post`: Create a new resource (asynchronous)
  - `put`: Replace resource (full update) (asynchronous)
  - `patch`: Update resource (partial update, recommended) (asynchronous)
  - `delete`: Delete a resource (synchronous)

### Resource-Specific Parameters

#### Tickets Resource

- **ticket_id** (conditional): Required for get, put, patch, and delete operations
- **body** (conditional): Required for post, put, and patch operations. Must contain a `ticket` object with the fields to create/update.

Example - Get ticket:
```json
{
  "domain": "support.example.com",
  "resource": "tickets",
  "method": "get",
  "ticket_id": 12345
}
```

Example - Create ticket:
```json
{
  "domain": "support.example.com",
  "resource": "tickets",
  "method": "post",
  "body": {
    "ticket": {
      "subject": "New support request",
      "comment": {
        "body": "I need help with my account"
      },
      "priority": "high"
    }
  }
}
```

Example - Update ticket:
```json
{
  "domain": "support.example.com",
  "resource": "tickets",
  "method": "patch",
  "ticket_id": 12345,
  "body": {
    "ticket": {
      "status": "solved",
      "comment": {
        "body": "Issue resolved",
        "public": true
      }
    }
  }
}
```

#### Users Resource

- **user_id** (conditional): Required for get, put, patch, and delete operations
- **body** (conditional): Required for post, put, and patch operations. Must contain a `user` object with the fields to create/update.

Example - Get user:
```json
{
  "domain": "support.example.com",
  "resource": "users",
  "method": "get",
  "user_id": 67890
}
```

Example - Create user:
```json
{
  "domain": "support.example.com",
  "resource": "users",
  "method": "post",
  "body": {
    "user": {
      "name": "Roger Wilco",
      "email": "roger@example.com",
      "role": "end-user"
    }
  }
}
```

Example - Update user:
```json
{
  "domain": "support.example.com",
  "resource": "users",
  "method": "patch",
  "user_id": 67890,
  "body": {
    "user": {
      "role": "agent",
      "phone": "+1-555-123-4567"
    }
  }
}
```

## Response Format

### Synchronous Operations (GET, DELETE)

Returns the Zendesk API response immediately:

```json
{
  "ticket": {
    "id": 12345,
    "subject": "Support request",
    "status": "open"
  }
}
```

### Asynchronous Operations (POST, PUT, PATCH)

Returns an acceptance confirmation:

```json
{
  "status": "accepted",
  "message": "Request queued for processing"
}
```

### Error Responses

```json
{
  "error": "Error description"
}
```

Common error status codes:
- **401**: Invalid or missing authentication secret
- **404**: Desk not found or inactive
- **422**: Invalid request parameters
- **500**: Internal server error

## Best Practices

1. **Use PATCH for updates**: PATCH is more efficient than PUT as it only updates specified fields.
2. **Handle async responses**: POST, PUT, and PATCH operations are asynchronous and return 202 Accepted.
3. **Check Zendesk API docs**: Refer to Zendesk API documentation for valid fields:
   - [Zendesk Tickets API](https://developer.zendesk.com/api-reference/ticketing/tickets/tickets/)
   - [Zendesk Users API](https://developer.zendesk.com/api-reference/ticketing/users/users/)
4. **Include comments in ticket updates**: When changing ticket status, always include a comment explaining the change.
5. **Use proper resource structure**: Always wrap data in the appropriate object (`ticket` or `user`).
6. **Secure your webhook**: Keep your `X-Webhook-Secret` secure and rotate it periodically.
7. **Specify the resource**: Always include the `resource` parameter to identify which Zendesk API to use.

## Migration from `/webhooks/tickets`

If you're migrating from the previous `/webhooks/tickets` endpoint:

1. Update the endpoint URL from `/webhooks/tickets` to `/webhooks/zendesk`
2. Add the `resource` parameter with value `"tickets"` to all requests
3. Update your secret environment variable from `WEBHOOKS_TICKETS_SECRET` to `WEBHOOKS_ZENDESK_SECRET` (optional but recommended)

Before:
```json
{
  "domain": "support.example.com",
  "method": "get",
  "ticket_id": 12345
}
```

After:
```json
{
  "domain": "support.example.com",
  "resource": "tickets",
  "method": "get",
  "ticket_id": 12345
}
```

## Related Documentation

- [Zendesk Tickets API Reference](https://developer.zendesk.com/api-reference/ticketing/tickets/tickets/)
- [Zendesk Users API Reference](https://developer.zendesk.com/api-reference/ticketing/users/users/)
- [Zendesk Rate Limiting](https://developer.zendesk.com/api-reference/introduction/rate-limits/)
