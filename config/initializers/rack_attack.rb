class Rack::Attack
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
  self.throttled_responder = lambda do |req|
    [
      429,
      {"Content-Type" => "text/plain"},
      ["Rate limit exceeded. Please retry later.\n"]
    ]
  end
end
