class ZendeskTicket < ApplicationRecord
  # Disable Rails automatic timestamps - we use Zendesk's timestamps directly
  self.record_timestamps = false

  # Set default timestamps if not provided (e.g., in tests or manual creation)
  before_validation :set_default_timestamps

  # Validations
  validates :zendesk_id, presence: true
  validates :domain, presence: true

  # Scopes
  scope :for_domain, ->(domain) { where(domain: domain) }
  scope :recent, -> { order(generated_timestamp: :desc) }

  # Ransack configuration for Avo search
  def self.ransackable_attributes(_auth_object = nil)
    %w[zendesk_id domain subject status priority ticket_type req_name req_email req_id assignee_name assignee_id
      group_name group_id organization_name]
  end

  # Access dynamic fields from raw_data
  # This allows accessing any field that might be in the JSONB column
  def method_missing(method, *args, &block)
    method_str = method.to_s
    # Check if it's a getter (no args, no block, not assignment)
    if args.empty? && !block_given? && !method_str.end_with?("=")
      # Try raw_data first
      return raw_data[method_str] if raw_data.is_a?(Hash) && raw_data.key?(method_str)

      # Try with underscore (e.g., created_at vs createdAt)
      if raw_data.is_a?(Hash)
        underscored_key = raw_data.keys.find { |k| k.to_s.underscore == method_str }
        return raw_data[underscored_key] if underscored_key
      end
    end
    super
  end

  def respond_to_missing?(method, include_private = false)
    method_str = method.to_s
    unless method_str.end_with?("=")
      return true if raw_data.is_a?(Hash) && raw_data.key?(method_str)
      return true if raw_data.is_a?(Hash) && raw_data.keys.any? { |k| k.to_s.underscore == method_str }
    end
    super
  end

  # Store all ticket data, extracting common fields to columns
  def assign_ticket_data(ticket_hash)
    # Ensure domain is set
    ticket_hash = ticket_hash.dup
    # Set domain from hash if provided, otherwise use existing domain
    if ticket_hash["domain"].present?
      self.domain = ticket_hash["domain"]
    elsif domain.present?
      ticket_hash["domain"] = domain
    end

    # Extract zendesk_id from 'id' field
    zendesk_id_value = ticket_hash["id"] || ticket_hash[:id] || ticket_hash["zendesk_id"] || ticket_hash[:zendesk_id]
    self.zendesk_id = zendesk_id_value if zendesk_id_value

    # Map common fields to columns
    field_mappings = {
      "subject" => :subject,
      "status" => :status,
      "priority" => :priority,
      "type" => :ticket_type,
      "url" => :url,
      # Nested objects (from Show Ticket API or when included)
      "requester" => ->(val) { extract_requester_fields(val) },
      "assignee" => ->(val) { extract_assignee_fields(val) },
      "group" => ->(val) { extract_group_fields(val) },
      "organization" => ->(val) { extract_organization_fields(val) },
      # Flat ID fields (from Incremental Export API - these are the primary fields)
      "requester_id" => :req_id,
      "assignee_id" => :assignee_id,
      "group_id" => :group_id,
      "organization_id" => lambda { |val|
        # Store organization_id in raw_data if we ever add the column
        # For now, it's accessible via raw_data
      },
      "submitter_id" => lambda { |val|
        # Store submitter_id in raw_data (not extracted to column yet)
      },
      # Support flat field names (for backward compatibility)
      "req_name" => :req_name,
      "req_email" => :req_email,
      "req_id" => :req_id,
      "req_external_id" => :req_external_id,
      "assignee_name" => :assignee_name,
      "assignee_external_id" => :assignee_external_id,
      "group_name" => :group_name,
      "organization_name" => :organization_name,
      "generated_timestamp" => :generated_timestamp,
      "created_at" => ->(val) { parse_time_field(val, :created_at) },
      "updated_at" => ->(val) { parse_time_field(val, :updated_at) },
      "assigned_at" => ->(val) { parse_time_field(val, :assigned_at) },
      "initially_assigned_at" => ->(val) { parse_time_field(val, :initially_assigned_at) },
      "solved_at" => ->(val) { parse_time_field(val, :solved_at) },
      "first_reply_time_in_minutes" => :first_reply_time_in_minutes,
      "first_reply_time_in_minutes_within_business_hours" => :first_reply_time_in_minutes_within_business_hours,
      "first_resolution_time_in_minutes" => :first_resolution_time_in_minutes,
      "first_resolution_time_in_minutes_within_business_hours" => :first_resolution_time_in_minutes_within_business_hours,
      "full_resolution_time_in_minutes" => :full_resolution_time_in_minutes,
      "full_resolution_time_in_minutes_within_business_hours" => :full_resolution_time_in_minutes_within_business_hours,
      "agent_wait_time_in_minutes" => :agent_wait_time_in_minutes,
      "agent_wait_time_in_minutes_within_business_hours" => :agent_wait_time_in_minutes_within_business_hours,
      "requester_wait_time_in_minutes" => :requester_wait_time_in_minutes,
      "requester_wait_time_in_minutes_within_business_hours" => :requester_wait_time_in_minutes_within_business_hours,
      "on_hold_time_in_minutes" => :on_hold_time_in_minutes,
      "on_hold_time_in_minutes_within_business_hours" => :on_hold_time_in_minutes_within_business_hours,
      "tags" => ->(val) { self.current_tags = Array(val).join(",") },
      "via" => :via,
      "resolution_time" => :resolution_time,
      "satisfaction_rating" => ->(val) { self.satisfaction_score = val.is_a?(Hash) ? val["score"]&.to_s : val.to_s },
      "group_stations" => :group_stations,
      "assignee_stations" => :assignee_stations,
      "reopens" => ->(val) { self.reopens = val.to_s },
      "replies" => ->(val) { self.replies = val.to_s },
      "due_at" => ->(val) { self.due_date = parse_time_field(val, nil)&.to_s }
    }

    # Process each field
    ticket_hash.each do |key, value|
      key_str = key.to_s
      next if %w[id domain].include?(key_str)

      next unless field_mappings.key?(key_str)

      mapping = field_mappings[key_str]
      if mapping.is_a?(Symbol)
        self[mapping] = value
      elsif mapping.is_a?(Proc)
        mapping.call(value)
      end
    end

    # Store complete raw data in JSONB
    self.raw_data = ticket_hash.deep_stringify_keys
  end

  # Store ticket metrics data, extracting nested time metrics and timestamp fields
  def assign_metrics_data(metrics_hash)
    return unless metrics_hash.is_a?(Hash)

    metrics_hash = metrics_hash.deep_stringify_keys

    # Extract nested time metrics (business/calendar hours)
    extract_nested_time_metric(metrics_hash, "reply_time_in_minutes", "first_reply_time_in_minutes")
    extract_nested_time_metric(metrics_hash, "first_resolution_time_in_minutes", "first_resolution_time_in_minutes")
    extract_nested_time_metric(metrics_hash, "full_resolution_time_in_minutes", "full_resolution_time_in_minutes")
    extract_nested_time_metric(metrics_hash, "agent_wait_time_in_minutes", "agent_wait_time_in_minutes")
    extract_nested_time_metric(metrics_hash, "requester_wait_time_in_minutes", "requester_wait_time_in_minutes")
    extract_nested_time_metric(metrics_hash, "on_hold_time_in_minutes", "on_hold_time_in_minutes")

    # Parse timestamp fields (only set if column exists)
    parse_time_field(metrics_hash["assigned_at"], :assigned_at)
    parse_time_field(metrics_hash["solved_at"], :solved_at)
    parse_time_field(metrics_hash["initially_assigned_at"], :initially_assigned_at)
    # Only parse these if columns exist (they may have been removed)
    parse_time_field(metrics_hash["status_updated_at"], :status_updated_at) if respond_to?(:status_updated_at=)
    if respond_to?(:latest_comment_added_at=)
      parse_time_field(metrics_hash["latest_comment_added_at"],
        :latest_comment_added_at)
    end
    parse_time_field(metrics_hash["requester_updated_at"], :requester_updated_at) if respond_to?(:requester_updated_at=)
    parse_time_field(metrics_hash["assignee_updated_at"], :assignee_updated_at) if respond_to?(:assignee_updated_at=)
    if respond_to?(:custom_status_updated_at=)
      parse_time_field(metrics_hash["custom_status_updated_at"],
        :custom_status_updated_at)
    end
    parse_time_field(metrics_hash["created_at"], :created_at)
    parse_time_field(metrics_hash["updated_at"], :updated_at)

    # Store count fields (schema has them as strings, so convert to string)
    self.reopens = metrics_hash["reopens"].to_s if metrics_hash.key?("reopens") && metrics_hash["reopens"]
    self.replies = metrics_hash["replies"].to_s if metrics_hash.key?("replies") && metrics_hash["replies"]
    if metrics_hash.key?("assignee_stations") && metrics_hash["assignee_stations"]
      self.assignee_stations = metrics_hash["assignee_stations"].to_s
    end
    if metrics_hash.key?("group_stations") && metrics_hash["group_stations"]
      self.group_stations = metrics_hash["group_stations"].to_s
    end

    # Store full metrics in raw_data
    self.raw_data = (raw_data || {}).merge("metrics" => metrics_hash.deep_stringify_keys)
  end

  private

  def set_default_timestamps
    now = Time.current
    self.created_at ||= now
    self.updated_at ||= now
  end

  def extract_requester_fields(requester)
    return unless requester.is_a?(Hash)

    self.req_name = requester["name"] || requester[:name]
    self.req_email = requester["email"] || requester[:email]
    self.req_id = requester["id"] || requester[:id]
    self.req_external_id = requester["external_id"]&.to_s || requester[:external_id]&.to_s
  end

  def extract_assignee_fields(assignee)
    return unless assignee.is_a?(Hash)

    self.assignee_name = assignee["name"] || assignee[:name]
    self.assignee_id = assignee["id"] || assignee[:id]
    self.assignee_external_id = assignee["external_id"] || assignee[:external_id]
  end

  def extract_group_fields(group)
    return unless group.is_a?(Hash)

    self.group_name = group["name"] || group[:name]
    self.group_id = group["id"] || group[:id]
  end

  def extract_organization_fields(organization)
    return unless organization.is_a?(Hash)

    self.organization_name = organization["name"] || organization[:name]
  end

  def parse_time_field(value, attribute = nil)
    return nil if value.nil?

    parsed_time = if value.is_a?(String)
      begin
        Time.parse(value)
      rescue ArgumentError
        nil
      end
    elsif value.is_a?(Time)
      value
    elsif value.is_a?(Integer)
      Time.at(value)
    end

    self[attribute] = parsed_time if attribute && parsed_time
    parsed_time
  end

  def extract_nested_time_metric(metrics_hash, api_key, column_base_name)
    time_metric = metrics_hash[api_key]
    return unless time_metric.is_a?(Hash)

    # Extract calendar value to main column
    calendar_value = time_metric["calendar"] || time_metric[:calendar]
    self[column_base_name.to_s] = calendar_value.to_i if calendar_value

    # Extract business value to _within_business_hours column
    business_value = time_metric["business"] || time_metric[:business]
    self["#{column_base_name}_within_business_hours"] = business_value.to_i if business_value
  end
end
