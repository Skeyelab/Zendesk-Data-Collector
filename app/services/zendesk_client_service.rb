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
        desk.save
      end
    end

    client
  end
end
