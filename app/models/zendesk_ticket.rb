class ZendeskTicket < ApplicationRecord
  # Validations
  validates :zendesk_id, presence: true
  validates :domain, presence: true

  # Scopes
  scope :for_domain, ->(domain) { where(domain: domain) }
  scope :recent, -> { order(generated_timestamp: :desc) }

  # Access dynamic fields from raw_data
  # This allows accessing any field that might be in the JSONB column
  def method_missing(method, *args, &block)
    method_str = method.to_s
    # Check if it's a getter (no args, no block, not assignment)
    if args.empty? && !block_given? && !method_str.end_with?('=')
      # Try raw_data first
      if raw_data.is_a?(Hash) && raw_data.key?(method_str)
        return raw_data[method_str]
      end
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
    if !method_str.end_with?('=')
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
    if ticket_hash['domain'].present?
      self.domain = ticket_hash['domain']
    elsif domain.present?
      ticket_hash['domain'] = domain
    end

    # Extract zendesk_id from 'id' field
    zendesk_id_value = ticket_hash['id'] || ticket_hash[:id] || ticket_hash['zendesk_id'] || ticket_hash[:zendesk_id]
    self.zendesk_id = zendesk_id_value if zendesk_id_value

    # Map common fields to columns
    field_mappings = {
      'subject' => :subject,
      'status' => :status,
      'priority' => :priority,
      'type' => :ticket_type,
      'url' => :url,
      'requester' => ->(val) { extract_requester_fields(val) },
      'assignee' => ->(val) { extract_assignee_fields(val) },
      'group' => ->(val) { extract_group_fields(val) },
      'organization' => ->(val) { extract_organization_fields(val) },
      # Support flat field names (for backward compatibility and direct API responses)
      'req_name' => :req_name,
      'req_email' => :req_email,
      'req_id' => :req_id,
      'req_external_id' => :req_external_id,
      'assignee_name' => :assignee_name,
      'assignee_id' => :assignee_id,
      'assignee_external_id' => :assignee_external_id,
      'group_name' => :group_name,
      'group_id' => :group_id,
      'organization_name' => :organization_name,
      'generated_timestamp' => :generated_timestamp,
      'created_at' => ->(val) { parse_time_field(val, :created_at) },
      'updated_at' => ->(val) { parse_time_field(val, :updated_at) },
      'assigned_at' => ->(val) { parse_time_field(val, :assigned_at) },
      'initially_assigned_at' => ->(val) { parse_time_field(val, :initially_assigned_at) },
      'solved_at' => ->(val) { parse_time_field(val, :solved_at) },
      'first_reply_time_in_minutes' => :first_reply_time_in_minutes,
      'first_reply_time_in_minutes_within_business_hours' => :first_reply_time_in_minutes_within_business_hours,
      'first_resolution_time_in_minutes' => :first_resolution_time_in_minutes,
      'first_resolution_time_in_minutes_within_business_hours' => :first_resolution_time_in_minutes_within_business_hours,
      'full_resolution_time_in_minutes' => :full_resolution_time_in_minutes,
      'full_resolution_time_in_minutes_within_business_hours' => :full_resolution_time_in_minutes_within_business_hours,
      'agent_wait_time_in_minutes' => :agent_wait_time_in_minutes,
      'agent_wait_time_in_minutes_within_business_hours' => :agent_wait_time_in_minutes_within_business_hours,
      'requester_wait_time_in_minutes' => :requester_wait_time_in_minutes,
      'requester_wait_time_in_minutes_within_business_hours' => :requester_wait_time_in_minutes_within_business_hours,
      'on_hold_time_in_minutes' => :on_hold_time_in_minutes,
      'on_hold_time_in_minutes_within_business_hours' => :on_hold_time_in_minutes_within_business_hours,
      'tags' => ->(val) { self.current_tags = Array(val).join(',') },
      'via' => :via,
      'resolution_time' => :resolution_time,
      'satisfaction_rating' => ->(val) { self.satisfaction_score = val.is_a?(Hash) ? val['score']&.to_s : val.to_s },
      'group_stations' => :group_stations,
      'assignee_stations' => :assignee_stations,
      'reopens' => ->(val) { self.reopens = val.to_s },
      'replies' => ->(val) { self.replies = val.to_s },
      'due_at' => ->(val) { self.due_date = parse_time_field(val, nil)&.to_s }
    }

    # Process each field
    ticket_hash.each do |key, value|
      key_str = key.to_s
      next if key_str == 'id' || key_str == 'domain'

      if field_mappings.key?(key_str)
        mapping = field_mappings[key_str]
        if mapping.is_a?(Symbol)
          self[mapping] = value
        elsif mapping.is_a?(Proc)
          mapping.call(value)
        end
      end
    end

    # Store complete raw data in JSONB
    self.raw_data = ticket_hash.deep_stringify_keys
  end

  private

  def extract_requester_fields(requester)
    return unless requester.is_a?(Hash)

    self.req_name = requester['name'] || requester[:name]
    self.req_email = requester['email'] || requester[:email]
    self.req_id = requester['id'] || requester[:id]
    self.req_external_id = requester['external_id']&.to_s || requester[:external_id]&.to_s
  end

  def extract_assignee_fields(assignee)
    return unless assignee.is_a?(Hash)

    self.assignee_name = assignee['name'] || assignee[:name]
    self.assignee_id = assignee['id'] || assignee[:id]
    self.assignee_external_id = assignee['external_id'] || assignee[:external_id]
  end

  def extract_group_fields(group)
    return unless group.is_a?(Hash)

    self.group_name = group['name'] || group[:name]
    self.group_id = group['id'] || group[:id]
  end

  def extract_organization_fields(organization)
    return unless organization.is_a?(Hash)

    self.organization_name = organization['name'] || organization[:name]
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
                  else
                    nil
                  end

    self[attribute] = parsed_time if attribute && parsed_time
    parsed_time
  end
end
