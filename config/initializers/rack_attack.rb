class Rack::Attack
  # Throttle login attempts by IP
  throttle("logins/ip", limit: 5, period: 20.seconds) do |req|
    if req.path == "/admin_users/sign_in" && req.post?
      req.ip
    end
  end

  # Throttle login attempts by email
  throttle("logins/email", limit: 5, period: 60.seconds) do |req|
    if req.path == "/admin_users/sign_in" && req.post?
      req.params.dig("admin_user", "email")&.downcase&.strip
    end
  end

  # Block suspicious requests
  blocklist("block bad IPs") do |req|
    # Add known bad IPs or ranges here
    # Rack::Attack::Fail2Ban.filter(...)
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |req|
    [429, { "Content-Type" => "text/plain" }, 
     ["Rate limit exceeded. Please retry later.\n"]]
  end
end
