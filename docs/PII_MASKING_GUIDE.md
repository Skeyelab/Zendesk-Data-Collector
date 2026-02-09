# PII Masking Guide for Developers

This guide explains how to handle Personally Identifiable Information (PII) in the Zendesk Data Collector application.

## Overview

The application implements a **three-tier PII protection strategy**:
1. **Encryption at rest** for highly sensitive fields (emails, external IDs)
2. **Display masking** for showing data in admin interfaces
3. **Audit logging** for tracking PII access

## What is PII?

In this application, PII includes:
- **Names**: Customer names, agent names
- **Email addresses**: Any email address
- **Phone numbers**: Contact phone numbers
- **Free text**: Ticket descriptions, comments (may contain sensitive info)
- **External IDs**: Customer identifiers from external systems

## Using PII Masking

### In Models

The `PiiMaskable` concern provides masking methods for models:

```ruby
class ZendeskTicket < ApplicationRecord
  include PiiMaskable
end

# Usage
ticket = ZendeskTicket.find(123)

# Access unmasked data (only in authorized contexts)
ticket.req_email          # => "john.doe@example.com"
ticket.req_name           # => "John Doe"

# Access masked data (safe for display)
ticket.masked_req_email   # => "j***@example.com"
ticket.masked_req_name    # => "J*** D***"
```

### In Views

Use the `PiiHelper` in views to mask data:

```erb
<!-- In ERB views -->
<%= mask_email(@ticket.req_email) %>
<%= mask_name(@ticket.req_name) %>
<%= mask_phone(@ticket.phone_number) %>
```

### Redacting raw_data

The `raw_data` JSONB field contains nested PII that should be redacted for display:

```ruby
# Get redacted version (safe for display)
redacted_data = ticket.pii_redacted_raw_data

# Original data is unchanged
ticket.raw_data  # Still contains full data
```

### Comment Metadata vs Content

Use metadata methods to show comment info without exposing content:

```ruby
# Get count without content
ticket.comments_count  # => 5

# Check if comments exist
ticket.has_comments?   # => true

# Get metadata only (no content)
metadata = ticket.comments_metadata
# => [{id: 1, author_id: 123, created_at: "...", body_length: 45}, ...]
```

## Masking Functions

### Email Masking

```ruby
mask_email("john.doe@example.com")  # => "j***@example.com"
mask_email("a@test.co")             # => "a***@test.co"
mask_email(nil)                     # => nil
```

**Rules**:
- Shows first character of local part
- Preserves full domain
- Returns nil for nil input

### Name Masking

```ruby
mask_name("John Doe")               # => "J*** D***"
mask_name("Mary")                   # => "M***"
mask_name("J Q Public")             # => "J*** Q*** P***"
```

**Rules**:
- Shows first character of each word
- Handles multiple names
- Returns nil for nil input

### Phone Masking

```ruby
mask_phone("+1-555-123-4567")       # => "***-4567"
mask_phone("5551234567")            # => "***4567"
mask_phone(nil)                     # => nil
```

**Rules**:
- Shows last 4 digits only
- Strips formatting
- Returns nil for nil input

### Text Content Masking

```ruby
mask_text_content("Long sensitive text...", show_length: true)
# => "[Content hidden - 123 characters]"

mask_text_content("Sensitive data", show_length: false)
# => "[Content hidden]"
```

**Rules**:
- Replaces content with summary
- Optionally shows character count
- Use for descriptions and comments

## In Avo Admin Interface

### Default Behavior

By default, all PII fields should be masked in list and detail views:

```ruby
# In Avo resource file
field :req_email, as: :text do
  value.present? ? record.masked_req_email : nil
end

field :req_name, as: :text do
  value.present? ? record.masked_req_name : nil
end
```

### Showing Unmasked PII

Only authorized users (admin role or higher) should be able to unmask PII:

```ruby
# Check permission
if current_user.can_unmask_pii?
  # Show unmasked data
  field :req_email_unmasked, as: :text, hide_on_index: true do
    record.req_email
  end
end
```

### raw_data Field

Always show redacted version by default:

```ruby
field :raw_data, as: :code, readonly: true, language: :json do
  JSON.pretty_generate(record.pii_redacted_raw_data)
end
```

## In API Responses

### Webhooks

Webhook responses should redact PII by default:

```ruby
# In controller
def show
  data = fetch_from_zendesk(ticket_id)
  
  # Redact PII unless explicitly requested
  if params[:include_pii] == "true" && current_user.can_view_pii?
    render json: data
  else
    render json: redact_response_pii(data)
  end
end
```

### Background Jobs

Background jobs should log ticket IDs and counts, but NOT PII content:

```ruby
# Good - no PII in logs
Rails.logger.info "Processing ticket #{ticket.zendesk_id}"

# Bad - PII in logs
Rails.logger.info "Processing ticket from #{ticket.req_email}"
```

## Access Control

### Checking Permissions

Always check permissions before showing unmasked PII:

```ruby
# In controllers
if current_user.can_unmask_pii?
  # Show unmasked data
  @email = ticket.req_email
else
  # Show masked data
  @email = ticket.masked_req_email
end
```

### Logging Access

When showing unmasked PII, log the access:

```ruby
if current_user.can_unmask_pii?
  # Log the access
  PiiAccessLog.create!(
    admin_user: current_user,
    resource_type: "ZendeskTicket",
    resource_id: ticket.id,
    field_name: "req_email",
    action: "unmask",
    ip_address: request.remote_ip
  )
  
  @email = ticket.req_email
end
```

## Testing PII Masking

### Unit Tests

```ruby
test "masks email correctly" do
  ticket = zendesk_tickets(:one)
  ticket.req_email = "test@example.com"
  
  assert_equal "t***@example.com", ticket.masked_req_email
end

test "redacts raw_data comments" do
  ticket = zendesk_tickets(:one)
  ticket.raw_data = {"comments" => [{"body" => "Sensitive"}]}
  
  redacted = ticket.pii_redacted_raw_data
  assert_match /\[Content hidden/, redacted["comments"][0]["body"]
end
```

### Integration Tests

```ruby
test "analyst cannot see unmasked email" do
  sign_in admin_users(:analyst)
  get avo.resource_path(ticket)
  
  assert_select ".email", text: /\*\*\*/
  assert_select ".unmask-button", count: 0
end

test "admin can unmask and access is logged" do
  sign_in admin_users(:admin)
  
  assert_difference "PiiAccessLog.count", 1 do
    post unmask_pii_path(ticket)
  end
end
```

## Best Practices

### DO ✅

- **Always mask PII by default** in UI displays
- **Use masked versions** when you don't need the real value
- **Check permissions** before showing unmasked data
- **Log PII access** for audit trail
- **Use metadata methods** (e.g., `comments_count`) when you don't need content
- **Test your masking** - write tests for new PII fields
- **Document PII fields** when adding new data to models

### DON'T ❌

- **Don't log PII** in Rails logs or job logs
- **Don't display unmasked PII** to unauthorized users
- **Don't send PII** in URLs or query parameters
- **Don't cache unmasked PII** in public caches
- **Don't include PII** in error messages
- **Don't modify raw_data** when using `pii_redacted_raw_data` (it creates a copy)
- **Don't assume a field is not PII** - when in doubt, mask it

## Common Patterns

### Pattern 1: List View with Masked Data

```ruby
# In Avo resource
field :req_email, as: :text, sortable: true do
  value.present? ? record.masked_req_email : nil
end
```

### Pattern 2: Detail View with Unmask Option

```ruby
# Show masked by default
field :req_email, as: :text, name: "Email (masked)" do
  record.masked_req_email
end

# Show unmask button if authorized
field :req_email_unmask, as: :heading, 
      hide_on_index: true,
      only_on: :show do
  if current_user.can_unmask_pii?
    link_to "View Unmasked Email", 
            unmask_field_path(record, field: "req_email"),
            class: "button"
  end
end
```

### Pattern 3: Raw Data Redaction

```ruby
# Always show redacted version
field :raw_data, as: :code, 
      readonly: true,
      language: :json do
  JSON.pretty_generate(record.pii_redacted_raw_data)
end

# Provide link to view full data if authorized
field :view_full_raw_data, as: :heading,
      hide_on_index: true do
  if current_user.can_unmask_pii?
    link_to "View Full Data (includes PII)",
            view_full_raw_data_path(record),
            class: "button button-danger"
  end
end
```

### Pattern 4: Conditional Display

```ruby
# In controller
def show
  @ticket = ZendeskTicket.find(params[:id])
  @show_pii = current_user.can_unmask_pii? && params[:show_pii] == "true"
  
  if @show_pii
    log_pii_access(@ticket, "view")
  end
end

# In view
<% if @show_pii %>
  <%= @ticket.req_email %>
<% else %>
  <%= @ticket.masked_req_email %>
<% end %>
```

## Adding New PII Fields

When adding a new field that contains PII:

1. **Identify the PII type** (name, email, phone, text, etc.)
2. **Add masking method** to `PiiMaskable` concern if needed
3. **Update Avo resource** to mask by default
4. **Add tests** for the new field
5. **Document** in `PII_PROTECTION_AUDIT.md`
6. **Consider encryption** if highly sensitive

Example:

```ruby
# 1. Add to model concern
def masked_phone_number
  return nil if phone_number.nil?
  mask_phone_internal(phone_number)
end

# 2. Update Avo resource
field :phone_number, as: :text do
  value.present? ? record.masked_phone_number : nil
end

# 3. Add test
test "masks phone number" do
  ticket.phone_number = "555-123-4567"
  assert_equal "***-4567", ticket.masked_phone_number
end

# 4. Document in audit
# Update PII_PROTECTION_AUDIT.md Appendix A table
```

## Encryption (Phase 2)

Some fields are encrypted at the database level:

```ruby
class ZendeskTicket < ApplicationRecord
  # These fields are automatically encrypted/decrypted
  encrypts :req_email, deterministic: true  # Allows searching
  encrypts :req_external_id                 # Non-deterministic (most secure)
end

# Usage is transparent
ticket.req_email = "test@example.com"
ticket.save!  # Encrypted automatically

ticket.reload
ticket.req_email  # => "test@example.com" (decrypted automatically)
```

**Notes**:
- Encryption is transparent to application code
- Encrypted fields appear as gibberish in database
- Deterministic encryption allows WHERE queries
- Non-deterministic encryption is most secure but no WHERE queries

## Compliance Notes

### GDPR Requirements

- **Right to Access**: Customers can request their data → provide unmasked export
- **Right to Erasure**: Customers can request deletion → implement deletion procedures
- **Data Minimization**: Only collect necessary data → audit what we store
- **Security**: Protect PII → encryption + masking + access control

### Data Retention

- Ticket data: 7 years (configurable)
- PII access logs: 90 days minimum
- Deleted records: Permanent removal, no soft-delete for PII

## Troubleshooting

### Problem: Masking breaks search

**Solution**: Use deterministic encryption for searchable fields:

```ruby
encrypts :req_email, deterministic: true
```

### Problem: Raw data queries are slow

**Solution**: Use selective redaction, not full-field encryption:

```ruby
# Fast - redacts on read
ticket.pii_redacted_raw_data

# Slow - encrypts entire JSONB field
encrypts :raw_data  # Don't do this
```

### Problem: Need to export unmasked data

**Solution**: Check permissions and log the export:

```ruby
if current_user.can_export_pii?
  log_pii_access(ticket, "export")
  ExportService.export_unmasked(tickets)
end
```

## Questions?

- See full audit: `docs/PII_PROTECTION_AUDIT.md`
- Implementation details: `app/models/concerns/pii_maskable.rb`
- Helper functions: `app/helpers/pii_helper.rb`
- Tests: `test/models/concerns/pii_maskable_test.rb`

## Version History

- **v1.0** (2026-02-09): Initial PII masking implementation
