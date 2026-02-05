require "digest"

class Rack::Attack
  # Allow webhook endpoint (n8n ticket/user updates) without throttling,
  # but only for callers presenting the correct shared secret header.
  safelist("webhooks/zendesk") do |req|
    next false unless req.path == "/webhooks/zendesk" && req.post?

    provided_secret = req.get_header("HTTP_X_WEBHOOK_SECRET")
    expected_secret = ENV["WEBHOOKS_ZENDESK_SECRET"] || ENV["WEBHOOKS_TICKETS_SECRET"]

    next false if provided_secret.nil? || expected_secret.nil?

    # secure_compare already prevents timing attacks, no need to hash
    ActiveSupport::SecurityUtils.secure_compare(provided_secret, expected_secret)
  end

  # Throttle login attempts by IP
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == "/admin_users/sign_in" && req.post?
  end

  # Throttle login attempts by email
  throttle("logins/email", limit: 5, period: 60.seconds) do |req|
    req.params.dig("admin_user", "email")&.downcase&.strip if req.path == "/admin_users/sign_in" && req.post?
  end

  # Block suspicious requests
  # Example usage: uncomment and add specific IPs to block
  # blocklist("block bad IPs") do |req|
  #   ["1.2.3.4", "5.6.7.8"].include?(req.ip)
  # end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |_req|
    [
      429,
      {"Content-Type" => "text/plain"},
      ["Rate limit exceeded. Please retry later.\n"]
    ]
  end
end
