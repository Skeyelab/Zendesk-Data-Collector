class ZendeskClientService
  def self.connect(desk)
    client = ZendeskAPI::Client.new do |config|
      config.url = "https://#{desk.domain}/api/v2"
      config.username = desk.user
      config.token = desk.token
      config.retry = false
    end

    client.insert_callback do |env|
      if env[:status] == 429
        retry_after = (env[:response_headers][:retry_after] || 10).to_i
        desk.wait_till = retry_after + Time.now.to_i
        begin
          desk.save!
        rescue StandardError => e
          Rails.logger.error("Failed to persist rate limit data for Desk ##{desk.id}: #{e.class}: #{e.message}") if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        end
      end
    end

    client
  end
end
