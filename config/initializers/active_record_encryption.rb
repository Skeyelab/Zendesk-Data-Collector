# Configure ActiveRecord Encryption
# Rails 8 requires encryption keys to be set for encrypted attributes
# This can be done via environment variables or Rails credentials

require "securerandom"

# Helper to get env var or nil (handles empty strings)
def encryption_env(key)
  value = ENV[key]
  (value && !value.empty?) ? value : nil
end

# Primary key: 32 bytes for encryption
Rails.application.config.active_record.encryption.primary_key =
  encryption_env("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY") ||
  Rails.application.credentials.dig(:active_record_encryption, :primary_key) ||
  # Generate a development/test key if neither is set
  (Rails.env.development? || Rails.env.test? ? SecureRandom.hex(32) : nil)

# Deterministic key: 32 bytes for deterministic encryption
Rails.application.config.active_record.encryption.deterministic_key =
  encryption_env("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY") ||
  Rails.application.credentials.dig(:active_record_encryption, :deterministic_key) ||
  # Generate a development/test key if neither is set
  (Rails.env.development? || Rails.env.test? ? SecureRandom.hex(32) : nil)

# Key derivation salt: used for key derivation
Rails.application.config.active_record.encryption.key_derivation_salt =
  encryption_env("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT") ||
  Rails.application.credentials.dig(:active_record_encryption, :key_derivation_salt) ||
  # Generate a development/test salt if neither is set
  (Rails.env.development? || Rails.env.test? ? SecureRandom.hex(32) : nil)
