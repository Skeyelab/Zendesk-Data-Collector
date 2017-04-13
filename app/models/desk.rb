class Desk < ApplicationRecord
  attr_encrypted :token, key: ENV["ENC_KEY"]
end
