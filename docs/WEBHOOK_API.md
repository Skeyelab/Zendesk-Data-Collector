# Zendesk Proxy Webhook API Documentation

## Overview

The Zendesk Proxy Webhook allows external systems (like n8n) to interact with Zendesk tickets through this application's rate-limited queue. This ensures that all Zendesk API calls are properly rate-limited and don't interfere with background sync operations.

## Authentication

All requests must include an `X-Webhook-Secret` header with the secret configured in the `WEBHOOKS_TICKETS_SECRET` environment variable.

```bash
X-Webhook-Secret: your_secret_here
```

## Endpoint

```
POST /webhooks/tickets
```

## Request Format

All requests must be sent as JSON with the following structure:

```json
{
  "domain": "your-subdomain.zendesk.com",
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

### Parameters

- **domain** (required): Your Zendesk domain (e.g., "support.example.com")
- **method** (optional): HTTP method to use. Default: "get"
  - `get`: Retrieve ticket information (synchronous)
  - `post`: Create a new ticket (asynchronous)
  - `put`: Replace ticket (full update) (asynchronous)
  - `patch`: Update ticket (partial update, recommended) (asynchronous)
  - `delete`: Delete a ticket (synchronous)
- **ticket_id** (conditional): Required for get, put, patch, and delete operations
- **body** (conditional): Required for post, put, and patch operations. Must contain a `ticket` object with the fields to create/update.

## Best Practices

1. **Use PATCH for updates**: PATCH is more efficient than PUT as it only updates specified fields.
2. **Handle async responses**: POST, PUT, and PATCH operations are asynchronous.
3. **Check Zendesk API docs**: Refer to [Zendesk API documentation](https://developer.zendesk.com/api-reference/ticketing/tickets/tickets/) for valid ticket fields.
4. **Include comments in updates**: When changing ticket status, always include a comment explaining the change.
5. **Use proper ticket structure**: Always wrap ticket data in a `ticket` object.
6. **Secure your webhook**: Keep your `X-Webhook-Secret` secure and rotate it periodically.

## Related Documentation

- [Zendesk API Reference](https://developer.zendesk.com/api-reference/ticketing/tickets/tickets/)
- [Zendesk Rate Limiting](https://developer.zendesk.com/api-reference/introduction/rate-limits/)
