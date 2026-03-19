# PII Protection Audit and Implementation Plan

**Date**: February 9, 2026  
**Application**: Zendesk Data Collector  
**Version**: 1.0  

---

## Executive Summary

This document provides a comprehensive audit of Personally Identifiable Information (PII) in the Zendesk Data Collector application and presents a phased implementation plan to protect PII while maintaining reporting capabilities.

### Key Findings

1. **PII Data Identified**: The application stores significant PII from Zendesk tickets including names, emails, and potentially sensitive information in ticket descriptions and comments
2. **Current Protection**: API tokens are encrypted, but customer PII is stored in plain text
3. **Access Points**: PII is accessible through Avo admin interface, API endpoints, and raw database queries
4. **Risk Level**: Medium - PII is stored unencrypted but access is restricted to authenticated admin users

### Recommended Approach

Implement a **three-tier protection strategy**:
1. **Encryption at rest** for highly sensitive fields (emails, external IDs)
2. **Display masking** with role-based access control in admin interfaces
3. **Audit logging** for PII access tracking

---

## 1. PII Data Inventory

### 1.1 Database Schema Analysis

#### ZendeskTicket Model - Direct PII Fields

| Field Name | Data Type | PII Category | Sensitivity | Current Protection |
|------------|-----------|--------------|-------------|-------------------|
| `req_name` | string | Name | High | None |
| `req_email` | string | Email Address | High | None |
| `req_external_id` | string | External Identifier | Medium | None |
| `assignee_name` | string | Name | Medium | None |
| `assignee_external_id` | bigint | External Identifier | Medium | None |
| `organization_name` | string | Organization | Low | None |
| `subject` | string | Potentially PII | Medium | None |

#### ZendeskTicket Model - JSONB raw_data Field

The `raw_data` JSONB column stores the complete Zendesk API response and may contain:

| Nested Field | PII Category | Sensitivity | Location |
|--------------|--------------|-------------|----------|
| `comments[].body` | Free text | High | raw_data.comments |
| `comments[].author_id` | User ID | Medium | raw_data.comments |
| `description` | Free text | High | raw_data.description |
| `requester.name` | Name | High | raw_data.requester.name |
| `requester.email` | Email | High | raw_data.requester.email |
| `requester.phone` | Phone Number | High | raw_data.requester.phone |
| `assignee.email` | Email | Medium | raw_data.assignee.email |
| `custom_fields[]` | Variable | Variable | raw_data.custom_fields |
| `via.source.from` | Contact Info | Medium | raw_data.via.source |

**Note**: The `raw_data` field is indexed with GIN index for performance but is stored in plain text.

#### Desk Model

| Field Name | Data Type | PII Category | Sensitivity | Current Protection |
|------------|-----------|--------------|-------------|-------------------|
| `token` | text | API Credential | Critical | ✅ Encrypted |
| `user` | string | Username | Low | None |

#### AdminUser Model

| Field Name | Data Type | PII Category | Sensitivity | Current Protection |
|------------|-----------|--------------|-------------|-------------------|
| `email` | string | Email | High | None (internal users) |
| `current_sign_in_ip` | inet | IP Address | Medium | None |
| `last_sign_in_ip` | inet | IP Address | Medium | None |

### 1.2 Access Point Analysis

#### Avo Admin Interface (`/avo`)

**Access Level**: Authenticated admin users only (Devise authentication)

**Exposed PII**:
- All ZendeskTicket fields including names and emails
- Search functionality includes name and email fields
- Full `raw_data` displayed as formatted JSON (including comments and descriptions)
- No masking or redaction applied

**File**: `app/avo/resources/zendesk_ticket_resource.rb`

```ruby
# Current search includes PII fields unmasked
field :req_name, as: :text, sortable: true
field :req_email, as: :text, sortable: true
field :raw_data, as: :code, readonly: true, language: :json
```

#### Webhook API (`/webhooks/zendesk`)

**Access Level**: Secret-based authentication (X-Webhook-Secret header)

**Exposed PII**:
- GET operations return full Zendesk API response (synchronous)
- Response includes all PII fields from Zendesk
- No redaction applied to responses

**File**: `app/controllers/webhooks/zendesk_controller.rb`

**Risk**: External systems (like n8n) receive unredacted PII

#### Background Jobs

**PII Processing**:
- `IncrementalTicketJob`: Fetches and stores full ticket data including PII
- `FetchTicketCommentsJob`: Fetches comment text which may contain PII
- `FetchTicketMetricsJob`: Minimal PII exposure
- `ZendeskProxyJob`: Passes through PII in webhook responses

**Logging**: Jobs log ticket IDs and counts but not PII content

### 1.3 Data Flow Diagram

```
Zendesk API → IncrementalTicketJob → PostgreSQL (plain text)
                                           ↓
                                    ┌──────┴──────┐
                                    ↓             ↓
                              Avo Admin      Webhook API
                            (full access)   (full passthrough)
```

---

## 2. Risk Assessment

### 2.1 Current Risks

| Risk | Impact | Likelihood | Severity |
|------|--------|------------|----------|
| Unauthorized database access exposes PII | High | Low | **High** |
| Admin user account compromise | High | Low | **High** |
| Webhook secret leak exposes PII via API | Medium | Medium | **Medium** |
| Database backup exposure | High | Low | **High** |
| Logs containing PII | Low | Low | **Low** |
| Overly broad admin access | Medium | Medium | **Medium** |

### 2.2 Compliance Considerations

#### GDPR (General Data Protection Regulation)
- ✅ **Article 25**: Security by design - ⚠️ Partially implemented (authentication only)
- ❌ **Article 32**: Encryption of personal data - Not implemented
- ❌ **Article 30**: Records of processing activities - Not documented
- ❌ **Article 17**: Right to erasure - No deletion procedures
- ❌ **Article 15**: Right of access - No documented access procedures

#### CCPA (California Consumer Privacy Act)
- ❌ Data minimization - All Zendesk fields stored indefinitely
- ❌ Consumer rights - No documented procedures for data requests

#### SOC 2 / ISO 27001
- ⚠️ Access controls - Basic authentication in place
- ❌ Encryption at rest - Not implemented for PII
- ❌ Audit logging - Not implemented for PII access

---

## 3. Protection Strategy

### 3.1 Guiding Principles

1. **Minimize Impact on Reporting**: PII protection should not hinder legitimate analytics and reporting
2. **Defense in Depth**: Multiple layers of protection
3. **Role-Based Access**: Different visibility levels for different roles
4. **Audit Trail**: Log all PII access for compliance
5. **Backwards Compatible**: Gradual rollout without breaking existing functionality

### 3.2 Three-Tier Protection Model

#### Tier 1: Encryption at Rest (Database Level)
**Purpose**: Protect PII in database backups and unauthorized database access

**Implementation**:
- Use Rails 7+ ActiveRecord Encryption
- Encrypt highly sensitive fields: `req_email`, `req_external_id`, `assignee_external_id`
- Store encryption keys securely (already configured: `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`)

**Trade-offs**:
- ✅ Strong protection against database dumps
- ❌ Slight query performance impact (minimal)
- ❌ Cannot use SQL LIKE queries on encrypted fields (use deterministic encryption where needed)

**External System Integration Considerations**:
- **Deterministic encryption** preserves ability to join with external systems
- Same plaintext value always produces same encrypted value
- JOINs work: `JOIN external_db.users ON tickets.req_email = users.email`
- External systems must either:
  1. Use same encryption (requires sharing encryption keys - not recommended)
  2. Decrypt in application layer before joining (recommended)
  3. Use non-PII join keys like `req_id` or `req_external_id` (best practice)

**Recommendation for External Joins**:
- **Preferred**: Use `req_id` (Zendesk user ID) for joins instead of email
- **Alternative**: Decrypt email in application layer before passing to external system
- **Avoid**: Sharing encryption keys across systems (security risk)

#### Tier 2: Display Masking (Application Level)
**Purpose**: Prevent casual exposure of PII in admin interfaces

**Implementation**:
- Create PII masking helper methods
- Add role-based unmask permissions
- Mask by default, show on explicit action

**Examples**:
- Email: `john.doe@example.com` → `j***@example.com`
- Name: `John Doe` → `J*** D***`
- Comments: Show character count only, require explicit click to view

**Trade-offs**:
- ✅ Balance between privacy and usability
- ✅ Users can unmask when legitimate need exists
- ✅ No performance impact

#### Tier 3: Audit Logging (Compliance Level)
**Purpose**: Track who accessed what PII and when

**Implementation**:
- Log PII field access events
- Track unmask actions in Avo
- Retain logs for compliance periods (default: 90 days)

**Trade-offs**:
- ✅ Compliance evidence
- ✅ Incident investigation capability
- ❌ Storage overhead (minimal)

### 3.3 Special Handling: raw_data JSONB Field

**Challenge**: The `raw_data` field contains nested PII that's difficult to encrypt selectively

**Recommended Approaches**:

**Option A: Selective Redaction (Recommended)**
- Keep `raw_data` as-is for backwards compatibility
- Redact PII from `raw_data` before display in Avo
- Create a `pii_redacted_view` method that returns sanitized version
- Store full data, redact on read

```ruby
def pii_redacted_view
  redacted = raw_data.deep_dup
  redacted["comments"]&.each { |c| c["body"] = "[REDACTED]" }
  redacted["description"] = "[REDACTED]"
  # ... more redactions
  redacted
end
```

**Option B: Separate PII Storage**
- Extract PII from `raw_data` to encrypted fields
- Store non-PII analytical data in `raw_data`
- More complex but cleaner separation

**Option C: Full Field Encryption**
- Encrypt entire `raw_data` field
- ❌ Not recommended: Breaks GIN index performance
- ❌ Not recommended: Breaks JSONB queries

**Decision**: Implement Option A for Phase 1, evaluate Option B for Phase 2 if needed

---

## 4. Implementation Plan

### Phase 1: Foundation and Quick Wins (Week 1)

#### 1.1 Create PII Masking Infrastructure

**Files to create/modify**:
- `app/helpers/pii_helper.rb` - Masking utilities
- `app/models/concerns/pii_maskable.rb` - Model concern for PII masking

**Functionality**:
- Mask email addresses: `j***@example.com`
- Mask names: `J*** D***`
- Mask raw_data comments/descriptions

**Testing**:
- `test/helpers/pii_helper_test.rb`
- `test/models/concerns/pii_maskable_test.rb`

#### 1.2 Update Avo Resources with Masking

**Files to modify**:
- `app/avo/resources/zendesk_ticket_resource.rb`

**Changes**:
- Mask `req_email` and `req_name` by default
- Mask `assignee_name` and `assignee_email` (from raw_data)
- Add "Show PII" action/link to unmask for authorized users
- Use redacted raw_data view by default

**Testing**:
- Manual testing in Avo UI (screenshot required)
- `test/avo/zendesk_ticket_resource_test.rb` (if tests exist)

#### 1.3 Documentation

**Files to create**:
- `docs/PII_PROTECTION_AUDIT.md` ← This document
- `docs/PII_MASKING_GUIDE.md` - Developer guide for PII handling

---

### Phase 2: Encryption at Rest (Week 2)

#### 2.1 Add Column-Level Encryption

**Files to create**:
- `db/migrate/[timestamp]_encrypt_pii_fields.rb`

**Changes**:
- Encrypt `req_email` using deterministic encryption (allows searching AND joining with external systems)
- Encrypt `req_external_id` using non-deterministic encryption
- Encrypt `assignee_external_id` using non-deterministic encryption

**Important - External System Integration**:
The `req_email` field uses **deterministic encryption**, which means:
- ✅ Same email always encrypts to the same value
- ✅ WHERE clause equality searches work: `WHERE req_email = 'john@example.com'`
- ✅ JOINs with external systems work: `JOIN external_table ON zendesk_tickets.req_email = external_table.email`
- ✅ Application-level decryption is transparent (Rails handles it)
- ⚠️ External systems must use the same encryption keys to join on encrypted values
- ⚠️ For cross-system joins, consider using `req_id` (Zendesk user ID) instead of email

**Model updates**:
- `app/models/zendesk_ticket.rb` - Add encryption declarations

```ruby
class ZendeskTicket < ApplicationRecord
  encrypts :req_email, deterministic: true  # Allows searching and joining
  encrypts :req_external_id
  encrypts :assignee_external_id
end
```

**Migration for existing data**:
```ruby
class EncryptPiiFields < ActiveRecord::Migration[8.1]
  def up
    # Rails encryption will handle this automatically on save
    # But we need to trigger encryption for existing records
    ZendeskTicket.find_each do |ticket|
      ticket.save! if ticket.req_email.present? || 
                      ticket.req_external_id.present? || 
                      ticket.assignee_external_id.present?
    end
  end

  def down
    # Decryption happens automatically when reading
  end
end
```

**Testing**:
- `test/models/zendesk_ticket_encryption_test.rb`
- Verify encrypted values in database are not readable
- Verify application can still read/write fields

#### 2.2 Verify Encryption Keys

**Environment variables required**:
- `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` - Already configured
- `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` - Already configured
- `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` - Already configured

**Action**: Document key rotation procedures

---

### Phase 3: Access Control and Audit Logging (Week 3)

#### 3.1 Add PII Access Tracking

**Files to create**:
- `app/models/pii_access_log.rb`
- `db/migrate/[timestamp]_create_pii_access_logs.rb`

**Schema**:
```ruby
create_table :pii_access_logs do |t|
  t.references :admin_user, null: false
  t.string :resource_type, null: false  # "ZendeskTicket"
  t.integer :resource_id, null: false
  t.string :field_name, null: false      # "req_email", "raw_data.comments"
  t.string :action, null: false          # "view", "unmask", "export"
  t.inet :ip_address
  t.string :user_agent
  t.timestamps
end
```

**Model**:
```ruby
class PiiAccessLog < ApplicationRecord
  belongs_to :admin_user
  
  scope :recent, -> { where("created_at > ?", 90.days.ago) }
  scope :for_resource, ->(type, id) { 
    where(resource_type: type, resource_id: id) 
  }
end
```

#### 3.2 Implement Role-Based Access Control

**Files to modify**:
- `app/models/admin_user.rb` - Add role field
- `db/migrate/[timestamp]_add_role_to_admin_users.rb`
- `app/avo/resources/zendesk_ticket_resource.rb` - Role checks

**Roles**:
- `analyst`: Can view masked PII only, cannot unmask
- `admin`: Can unmask PII, actions are logged
- `super_admin`: Full access, actions are logged

**Implementation**:
```ruby
class AdminUser < ApplicationRecord
  enum role: { analyst: 0, admin: 1, super_admin: 2 }
  
  def can_unmask_pii?
    admin? || super_admin?
  end
end
```

#### 3.3 Add Avo Actions for Unmasking

**Files to create**:
- `app/avo/actions/view_pii_action.rb`

**Functionality**:
- "View PII" button on ticket detail page
- Checks user role
- Logs access event
- Returns unmasked data modal/popup

**Testing**:
- Manual testing with different roles
- Screenshot of masked vs unmasked views

---

### Phase 4: API and Webhook Protection (Week 4)

#### 4.1 Add PII Redaction to Webhook Responses

**Files to modify**:
- `app/jobs/zendesk_proxy_job.rb`
- `app/services/pii_redaction_service.rb` (new)

**Functionality**:
- Redact PII from GET responses based on configuration
- Add `include_pii` parameter to webhook API (default: false)
- Document in `docs/WEBHOOK_API.md`

**Configuration levels**:
- `full`: No redaction (legacy, requires explicit flag)
- `masked`: Email/name masking
- `none`: No PII in response (default)

#### 4.2 Update API Documentation

**Files to modify**:
- `docs/WEBHOOK_API.md`

**Additions**:
- PII handling section
- `include_pii` parameter documentation
- Security considerations
- Compliance guidelines

---

### Phase 5: Testing and Validation (Week 5)

#### 5.1 Comprehensive Test Suite

**Test files to create/update**:
- `test/helpers/pii_helper_test.rb` - Masking logic
- `test/models/pii_access_log_test.rb` - Audit logging
- `test/models/zendesk_ticket_encryption_test.rb` - Encryption
- `test/integration/pii_access_test.rb` - End-to-end access control
- `test/services/pii_redaction_service_test.rb` - API redaction

**Coverage goals**:
- Unit tests: > 90% coverage for new code
- Integration tests: Key user flows
- Security tests: Authorization checks

#### 5.2 Security Scanning

**Tools**:
- CodeQL (already configured in CI)
- Manual security review
- Dependency vulnerability scan

**Actions**:
- Run `codeql_checker` tool
- Address any findings
- Document residual risks

#### 5.3 Performance Testing

**Concerns**:
- Encryption overhead on large datasets
- GIN index performance with encrypted fields
- Masking performance in Avo views

**Benchmarks**:
- Time 1000 ticket inserts (with encryption)
- Time Avo index page load (with masking)
- Compare to baseline

---

### Phase 6: Documentation and Compliance (Week 6)

#### 6.1 Compliance Documentation

**Files to create**:
- `docs/GDPR_COMPLIANCE.md` - GDPR compliance statement
- `docs/DATA_RETENTION_POLICY.md` - Retention and deletion procedures
- `docs/PII_INCIDENT_RESPONSE.md` - Breach response plan
- `docs/PII_MASKING_GUIDE.md` - Developer guide

**Content**:
- Legal basis for processing
- Data subject rights procedures (access, rectification, erasure)
- Retention periods
- International data transfers
- Security measures

#### 6.2 Update Main Documentation

**Files to modify**:
- `README.md` - Add PII protection section
- `.github/copilot-instructions.md` - Add PII handling guidelines
- `docs/DEPLOYMENT.md` - Add encryption key setup

#### 6.3 Admin User Training

**Materials to create**:
- Admin guide for PII access
- Best practices document
- Video walkthrough (optional)

---

## 5. Maintenance and Ongoing Compliance

### 5.1 Regular Audits

**Quarterly tasks**:
- Review PII access logs for anomalies
- Verify encryption keys are properly secured
- Check for new PII fields in Zendesk API
- Update redaction rules as needed

### 5.2 Data Retention

**Recommendations**:
- Ticket data: Retain for 7 years (configurable)
- PII access logs: 90 days minimum, 1 year recommended
- Deleted tickets: Permanent removal (GDPR compliance)

**Implementation**:
- Create `rake tasks:cleanup_old_tickets` task
- Document data deletion procedures
- Add soft-delete option for compliance tracking

### 5.3 Key Rotation

**Schedule**: Annual or on security incident

**Procedure**:
1. Generate new encryption keys
2. Deploy new keys to all environments
3. Re-encrypt data with new keys (Rails handles automatically)
4. Retire old keys after grace period

**Documentation**: Document in `docs/ENCRYPTION_KEY_ROTATION.md`

---

## 6. Testing Strategy

### 6.1 Unit Tests

```ruby
# test/helpers/pii_helper_test.rb
class PiiHelperTest < ActionView::TestCase
  test "masks email addresses correctly" do
    assert_equal "j***@example.com", mask_email("john.doe@example.com")
    assert_equal "a***@ex.co", mask_email("admin@ex.co")
  end
  
  test "masks names correctly" do
    assert_equal "J*** D***", mask_name("John Doe")
    assert_equal "J***", mask_name("John")
  end
  
  test "handles nil values" do
    assert_nil mask_email(nil)
    assert_nil mask_name(nil)
  end
end
```

### 6.2 Integration Tests

```ruby
# test/integration/pii_access_test.rb
class PiiAccessTest < ActionDispatch::IntegrationTest
  test "analyst cannot unmask PII" do
    admin = admin_users(:analyst)
    sign_in admin
    
    ticket = zendesk_tickets(:one)
    get avo.resource_path(ticket)
    
    assert_select ".masked-email", text: /\*\*\*/
    assert_select ".unmask-button", count: 0
  end
  
  test "admin can unmask PII and access is logged" do
    admin = admin_users(:admin)
    sign_in admin
    
    ticket = zendesk_tickets(:one)
    
    assert_difference "PiiAccessLog.count", 1 do
      post unmask_pii_avo_zendesk_ticket_path(ticket)
    end
    
    log = PiiAccessLog.last
    assert_equal admin.id, log.admin_user_id
    assert_equal "ZendeskTicket", log.resource_type
    assert_equal ticket.id, log.resource_id
  end
end
```

### 6.3 Encryption Tests

```ruby
# test/models/zendesk_ticket_encryption_test.rb
class ZendeskTicketEncryptionTest < ActiveSupport::TestCase
  test "encrypts req_email" do
    ticket = ZendeskTicket.create!(
      zendesk_id: 12345,
      domain: "test.zendesk.com",
      req_email: "test@example.com"
    )
    
    # Check encrypted value in database
    raw_value = ActiveRecord::Base.connection.execute(
      "SELECT req_email FROM zendesk_tickets WHERE id = #{ticket.id}"
    ).first["req_email"]
    
    assert_not_equal "test@example.com", raw_value
    assert_equal "test@example.com", ticket.reload.req_email
  end
end
```

---

## 7. Alternative Approaches Considered

### 7.1 Full Field-Level Encryption (Rejected)

**Approach**: Encrypt all PII fields individually

**Pros**:
- Strongest protection
- Granular control

**Cons**:
- ❌ Cannot search encrypted fields (except deterministic)
- ❌ Significant performance impact
- ❌ Complex key management
- ❌ Breaks JSONB queries on raw_data

**Decision**: Use selective encryption for highest-risk fields only

### 7.2 Separate PII Database (Rejected)

**Approach**: Store PII in separate database with restricted access

**Pros**:
- Strong access control
- Easier to audit

**Cons**:
- ❌ Complex joins for reporting
- ❌ Significant refactoring required
- ❌ Operational overhead (two databases)

**Decision**: Single database with encryption and access controls is sufficient

### 7.3 Tokenization Service (Rejected)

**Approach**: Replace PII with tokens, store PII in external vault

**Pros**:
- Strong isolation
- Specialized security

**Cons**:
- ❌ External dependency
- ❌ Cost
- ❌ Latency for PII retrieval
- ❌ Overkill for this use case

**Decision**: Not justified for current scale and requirements

### 7.4 Complete PII Redaction (Rejected)

**Approach**: Don't store PII at all, only anonymized data

**Pros**:
- No PII exposure risk
- Simple compliance

**Cons**:
- ❌ Cannot troubleshoot customer issues
- ❌ Cannot link tickets to customers
- ❌ Defeats purpose of Zendesk integration

**Decision**: Not viable for support application

---

## 8. Rollout Plan

### 8.1 Development Environment

1. Enable PII masking
2. Test with sample data
3. Verify reporting still works

### 8.2 Staging Environment

1. Deploy masking changes
2. Run encryption migration on copy of production data
3. Performance testing
4. User acceptance testing

### 8.3 Production Rollout

**Phase 1: Non-Breaking Changes (Week 1-2)**
- Deploy PII masking (display only, no data changes)
- Monitor for issues
- Gather user feedback

**Phase 2: Encryption Migration (Week 3)**
- Schedule maintenance window (low impact)
- Run encryption migration
- Verify encrypted fields readable
- Rollback plan: Restore from backup

**Phase 3: Access Controls (Week 4)**
- Add role field to admin users
- Deploy audit logging
- Train admins on new workflows

**Phase 4: API Protection (Week 5-6)**
- Update webhook API with PII redaction
- Notify external system owners (n8n)
- Provide migration timeline

### 8.4 Rollback Procedures

**If masking causes issues**:
- Feature flag to disable masking
- Revert Avo resource changes

**If encryption causes issues**:
- Restore database from pre-migration backup
- Data loss: up to backup point
- Recommendation: Test thoroughly in staging

---

## 9. Cost-Benefit Analysis

### 9.1 Implementation Costs

| Phase | Time Estimate | Developer Cost (estimate) |
|-------|---------------|---------------------------|
| Phase 1: Masking | 20 hours | $2,000 |
| Phase 2: Encryption | 30 hours | $3,000 |
| Phase 3: Access Control | 25 hours | $2,500 |
| Phase 4: API Protection | 15 hours | $1,500 |
| Phase 5: Testing | 20 hours | $2,000 |
| Phase 6: Documentation | 10 hours | $1,000 |
| **Total** | **120 hours** | **$12,000** |

### 9.2 Ongoing Costs

- Key management: Minimal (handled by Rails)
- Audit log storage: ~100MB/year (negligible)
- Performance impact: <5% (estimated)
- Compliance audits: 8 hours/quarter = $8,000/year

### 9.3 Benefits

**Risk Reduction**:
- Reduced breach impact: Encrypted data less valuable
- Compliance readiness: GDPR, CCPA compliant
- Customer trust: Demonstrates security commitment
- Legal protection: Defensible data handling

**Quantified Benefits**:
- Avoid GDPR fines: Up to €20M or 4% revenue (worst case)
- Avoid breach costs: $4.45M average cost per breach (IBM)
- Insurance premium reduction: 10-20% potential
- Customer retention: 65% customers leave after breach

**ROI**: Even preventing a single breach pays for implementation 100x over

---

## 10. Success Metrics

### 10.1 Technical Metrics

- **Encryption coverage**: 100% of identified high-risk PII fields encrypted
- **Test coverage**: >90% for PII-related code
- **Performance impact**: <5% increase in query time
- **Masking effectiveness**: 100% of PII fields masked in default Avo views

### 10.2 Compliance Metrics

- **Audit log retention**: 100% of PII access events logged
- **GDPR readiness**: All Article 32 requirements met
- **Data deletion**: Ability to fully delete user data within 30 days
- **Access control**: Role-based access enforced on all PII

### 10.3 Operational Metrics

- **Admin satisfaction**: Survey score >4/5 after training
- **Support ticket resolution**: No degradation in time to resolve
- **Reporting accuracy**: 100% of reports still functioning
- **False positive unmasks**: <10% of unmask actions unnecessary

---

## 11. Recommendations

### 11.1 Immediate Actions (Do First)

1. ✅ **Create this audit document** - Establishes baseline
2. 🏃 **Implement PII masking in Avo** - Quick win, non-breaking, immediate privacy improvement
3. 🏃 **Add audit logging** - Start tracking before adding access controls

**Timeline**: Week 1-2  
**Risk**: Low  
**Impact**: Medium  

### 11.2 Short-Term Actions (Within 1 Month)

4. 🎯 **Encrypt high-risk fields** - req_email, external IDs
5. 🎯 **Add role-based access control** - Different admin access levels
6. 🎯 **Update webhook API** - Add PII redaction option

**Timeline**: Week 3-4  
**Risk**: Medium (test thoroughly)  
**Impact**: High  

### 11.3 Long-Term Actions (Within 3 Months)

7. 📅 **Complete GDPR documentation** - Compliance evidence
8. 📅 **Implement data retention policy** - Automated cleanup
9. 📅 **Key rotation procedures** - Security best practice

**Timeline**: Month 2-3  
**Risk**: Low  
**Impact**: Medium  

### 11.4 Optional Enhancements (Future)

- **Data anonymization**: For analytics/reporting environments
- **PII discovery automation**: Scan for new PII fields automatically
- **User self-service**: Allow customers to request their data
- **Blockchain audit trail**: Immutable PII access logging (if needed for compliance)

---

## 12. Conclusion

The Zendesk Data Collector application stores significant PII but currently lacks adequate protection beyond authentication. This audit identifies specific risks and provides a practical, phased implementation plan to protect PII while maintaining reporting functionality.

**Key Takeaways**:

1. **Current State**: Medium risk - PII stored in plain text, access controlled only by authentication
2. **Recommended Approach**: Three-tier protection (encryption + masking + audit logging)
3. **Implementation**: Phased rollout over 6 weeks, minimal breaking changes
4. **Cost**: ~120 hours development time, <5% performance impact
5. **Benefit**: GDPR/CCPA compliance, reduced breach risk, customer trust

**Next Steps**:

1. Review this document with stakeholders
2. Prioritize phases based on business needs
3. Begin Phase 1 implementation (PII masking)
4. Schedule regular audits (quarterly)

**Document Version**: 1.0  
**Last Updated**: February 9, 2026  
**Next Review**: May 9, 2026  

---

## Appendix A: PII Field Reference

| Model | Field | Data Type | PII Category | Encryption | Masking |
|-------|-------|-----------|--------------|------------|---------|
| ZendeskTicket | req_name | string | Name | - | ✅ |
| ZendeskTicket | req_email | string | Email | ✅ Deterministic | ✅ |
| ZendeskTicket | req_external_id | string | External ID | ✅ | - |
| ZendeskTicket | assignee_name | string | Name | - | ✅ |
| ZendeskTicket | assignee_external_id | bigint | External ID | ✅ | - |
| ZendeskTicket | raw_data.comments | jsonb | Free text | - | ✅ |
| ZendeskTicket | raw_data.description | jsonb | Free text | - | ✅ |
| ZendeskTicket | raw_data.requester | jsonb | Various | - | ✅ |
| AdminUser | email | string | Email | - | - |
| AdminUser | current_sign_in_ip | inet | IP Address | - | - |
| Desk | token | text | API Token | ✅ | - |

## Appendix B: Glossary

- **PII**: Personally Identifiable Information - any data that can identify an individual
- **GDPR**: General Data Protection Regulation - EU privacy law
- **CCPA**: California Consumer Privacy Act - California privacy law
- **Deterministic Encryption**: Encryption where same input always produces same output (allows searching)
- **Non-Deterministic Encryption**: Encryption where same input produces different output (highest security)
- **Masking**: Hiding part of data for display (e.g., j***@example.com)
- **Redaction**: Removing data entirely from output
- **Audit Logging**: Recording who accessed what data and when

## Appendix C: References

- [GDPR Official Text](https://gdpr-info.eu/)
- [Rails ActiveRecord Encryption](https://guides.rubyonrails.org/active_record_encryption.html)
- [OWASP Top 10 Privacy Risks](https://owasp.org/www-project-top-10-privacy-risks/)
- [Zendesk Security](https://www.zendesk.com/security/)
- [PostgreSQL Column Encryption](https://www.postgresql.org/docs/current/encryption-options.html)
