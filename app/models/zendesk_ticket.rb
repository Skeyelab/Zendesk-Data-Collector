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

    # Handle metric_sets if present (sideloaded ticket metrics)
    # Metric sets may contain additional time fields like status_updated_at, etc.
    # They can be in different formats:
    # 1. Flat in ticket_hash (already processed below)
    # 2. Nested in 'metric_sets' array
    # 3. Nested in 'metrics' hash
    if ticket_hash['metric_sets'].is_a?(Array) && ticket_hash['metric_sets'].any?
      # Use the most recent metric set
      metric_set = ticket_hash['metric_sets'].first
      if metric_set.is_a?(Hash)
        # Merge metric set fields into ticket_hash for processing
        metric_set.each do |key, value|
          # Only merge time/metric fields if not already present in ticket_hash
          time_fields = ['status_updated_at', 'latest_comment_added_at', 'requester_updated_at',
                        'assignee_updated_at', 'custom_status_updated_at', 'assigned_at',
                        'initially_assigned_at', 'solved_at']
          if time_fields.include?(key.to_s) && !ticket_hash.key?(key)
            ticket_hash[key] = value
          end
        end
      end
    elsif ticket_hash['metrics'].is_a?(Hash)
      # Handle metrics as a nested hash
      ticket_hash['metrics'].each do |key, value|
        time_fields = ['status_updated_at', 'latest_comment_added_at', 'requester_updated_at',
                      'assignee_updated_at', 'custom_status_updated_at', 'assigned_at',
                      'initially_assigned_at', 'solved_at']
        if time_fields.include?(key.to_s) && !ticket_hash.key?(key)
          ticket_hash[key] = value
        end
      end
    end

    # Map common fields to columns
    field_mappings = {
      'subject' => :subject,
      'status' => :status,
      'priority' => :priority,
      'type' => :ticket_type,
      'url' => :url,
      # Nested objects (from Show Ticket API or when included)
      'requester' => ->(val) { extract_requester_fields(val) },
      'assignee' => ->(val) { extract_assignee_fields(val) },
      'group' => ->(val) { extract_group_fields(val) },
      'organization' => ->(val) { extract_organization_fields(val) },
      # Flat ID fields (from Incremental Export API - these are the primary fields)
      'requester_id' => :req_id,
      'assignee_id' => :assignee_id,
      'group_id' => :group_id,
      'organization_id' => ->(val) {
        # Store organization_id in raw_data if we ever add the column
        # For now, it's accessible via raw_data
      },
      'submitter_id' => ->(val) {
        # Store submitter_id in raw_data (not extracted to column yet)
      },
      # Support flat field names (for backward compatibility)
      'req_name' => :req_name,
      'req_email' => :req_email,
      'req_id' => :req_id,
      'req_external_id' => :req_external_id,
      'assignee_name' => :assignee_name,
      'assignee_external_id' => :assignee_external_id,
      'group_name' => :group_name,
      'organization_name' => :organization_name,
      'generated_timestamp' => :generated_timestamp,
      # Store Zendesk timestamps separately from Rails timestamps
      'created_at' => ->(val) { parse_time_field(val, :zendesk_created_at) },
      'updated_at' => ->(val) { parse_time_field(val, :zendesk_updated_at) },
      'assigned_at' => ->(val) { parse_time_field(val, :assigned_at) },
      'initially_assigned_at' => ->(val) { parse_time_field(val, :initially_assigned_at) },
      'solved_at' => ->(val) { parse_time_field(val, :solved_at) },
      # Ticket Metrics time fields (available when metric_sets are sideloaded)
      'status_updated_at' => ->(val) { parse_time_field(val, :status_updated_at) },
      'latest_comment_added_at' => ->(val) { parse_time_field(val, :latest_comment_added_at) },
      'requester_updated_at' => ->(val) { parse_time_field(val, :requester_updated_at) },
      'assignee_updated_at' => ->(val) { parse_time_field(val, :assignee_updated_at) },
      'custom_status_updated_at' => ->(val) { parse_time_field(val, :custom_status_updated_at) },
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
      'due_at' => ->(val) {
        parsed = parse_time_field(val, :due_at)
        # Also store as string in due_date for backward compatibility
        self.due_date = parsed&.to_s if parsed
      }
    }

    # Normalize field name for matching (handle camelCase, snake_case, etc.)
    normalize_key = ->(key) { key.to_s.downcase.underscore.gsub(/-/, '_') }

    # Create normalized mapping lookup
    normalized_mappings = {}
    field_mappings.each do |k, v|
      normalized_mappings[normalize_key.call(k)] = { original_key: k, mapping: v }
    end

    # Process each field
    ticket_hash.each do |key, value|
      key_str = key.to_s
      normalized_key = normalize_key.call(key_str)
      next if normalized_key == 'id' || normalized_key == 'domain'

      # Try exact match first, then normalized match
      mapping_entry = if field_mappings.key?(key_str)
                        { mapping: field_mappings[key_str] }
                      elsif normalized_mappings.key?(normalized_key)
                        normalized_mappings[normalized_key]
                      else
                        nil
                      end

      if mapping_entry
        mapping = mapping_entry[:mapping]
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
                    # Handle ISO 8601 format strings
                    if value.empty?
                      nil
                    else
                      begin
                        Time.parse(value)
                      rescue ArgumentError => e
                        Rails.logger.warn "[ZendeskTicket] Failed to parse time field '#{attribute}' value '#{value}': #{e.message}" if defined?(Rails)
                        nil
                      end
                    end
                  elsif value.is_a?(Time)
                    value
                  elsif value.is_a?(DateTime)
                    value.to_time
                  elsif value.is_a?(Integer)
                    # Handle Unix timestamps (both seconds and milliseconds)
                    if value > 1_000_000_000_000 # milliseconds
                      Time.at(value / 1000.0)
                    else # seconds
                      Time.at(value)
                    end
                  elsif value.is_a?(Float)
                    # Handle Unix timestamps as floats
                    Time.at(value)
                  elsif value.is_a?(Hash) && value['timestamp']
                    # Handle nested timestamp objects
                    parse_time_field(value['timestamp'], attribute)
                  else
                    Rails.logger.warn "[ZendeskTicket] Unknown time field type for '#{attribute}': #{value.class}" if defined?(Rails)
                    nil
                  end

    if attribute && parsed_time
      self[attribute] = parsed_time
    elsif attribute && value.present?
      # Log when we have a value but couldn't parse it
      Rails.logger.warn "[ZendeskTicket] Could not parse time field '#{attribute}' with value: #{value.inspect}" if defined?(Rails)
    end

    parsed_time
  end
end
