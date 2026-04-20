# Security headers configuration
# These headers help protect against common web vulnerabilities

Rails.application.config.action_dispatch.default_headers = {
  "X-Frame-Options" => "SAMEORIGIN",
  "X-Content-Type-Options" => "nosniff",
  "X-XSS-Protection" => "0",
  "Referrer-Policy" => "strict-origin-when-cross-origin",
  "Permissions-Policy" => "geolocation=(), microphone=(), camera=()"
}
