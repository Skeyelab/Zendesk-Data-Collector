begin
  Mongoid.load!(Rails.root.join('config', 'mongoid.yml'))

  if Rails.env.production?
    # Validate MONGODB_URI is set and not empty
    mongodb_uri = ENV['MONGODB_URI'].to_s.strip
    if mongodb_uri.empty? || mongodb_uri == 'NOT_SET'
      error_msg = "MONGODB_URI environment variable is required in production but is not set or is empty"
      Rails.logger.error "ERROR: #{error_msg}"
      raise error_msg
    end

    # Check if URI format is valid
    unless mongodb_uri.match?(/\Amongodb\+?s?:\/\//i)
      error_msg = "MONGODB_URI format is invalid. Expected format: mongodb://host:port/database or mongodb+srv://..."
      Rails.logger.error "ERROR: #{error_msg}"
      Rails.logger.error "Current value starts with: #{mongodb_uri[0..20]}..."
      raise error_msg
    end

    Rails.logger.info "MongoDB URI configured: #{mongodb_uri.gsub(/\/\/[^:]+:[^@]+@/, '//****:****@')}" # Mask credentials in logs

    # Test connection
    begin
      Mongoid.default_client.database.command(ping: 1)
      Rails.logger.info "MongoDB connection successful"
    rescue Mongo::Error::ServerNotAvailable, Mongo::Error::NoServerAvailable => e
      Rails.logger.error "MongoDB server not available: #{e.class}: #{e.message}"
      Rails.logger.error "Connection string format: #{mongodb_uri.match(/mongodb\+?s?:\/\/[^\/]+/i)&.to_s || 'INVALID'}"
      raise "Failed to connect to MongoDB server: #{e.message}"
    rescue Mongo::Error => e
      Rails.logger.error "MongoDB connection error: #{e.class}: #{e.message}"
      Rails.logger.error "Connection string format: #{mongodb_uri.match(/mongodb\+?s?:\/\/[^\/]+/i)&.to_s || 'INVALID'}"
      raise "Failed to connect to MongoDB: #{e.message}"
    rescue => e
      Rails.logger.error "Unexpected error connecting to MongoDB: #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      raise "Failed to connect to MongoDB: #{e.message}"
    end
  end
rescue => e
  Rails.logger.error "Failed to initialize Mongoid: #{e.class}: #{e.message}"
  Rails.logger.error e.backtrace.join("\n")
  raise
end
