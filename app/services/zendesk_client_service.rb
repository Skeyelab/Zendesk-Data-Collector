class ZendeskClientService
  # Persist desk.wait_till from 429 Retry-After without relying on desk.save! (avoids validation/encryption issues).
  # See: https://developer.zendesk.com/documentation/api-basics/best-practices/best-practices-for-avoiding-rate-limiting/
  def self.persist_wait_till_from_429(desk, env)
    return unless env && env[:status] == 429

    retry_after = ZendeskApiHeaders.extract_retry_after(env, 10)
    new_wait_till = retry_after + Time.now.to_i
    Desk.where(id: desk.id).update_all(wait_till: new_wait_till)
  end

  def self.connect(desk)
    client = ZendeskAPI::Client.new do |config|
      config.url = "https://#{desk.domain}/api/v2"
      config.username = desk.user
      config.token = desk.token
      config.retry = false
    end

    client.insert_callback do |env|
      persist_wait_till_from_429(desk, env)
    end

    client
  end
end
