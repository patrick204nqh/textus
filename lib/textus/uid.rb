require "securerandom"

module Textus
  # A Textus UID: 16 lowercase hex chars (SecureRandom.hex(8)). Not a UUID —
  # short on purpose. Random enough for collision-never-in-practice within a
  # single store.
  module Uid
    module_function

    def mint
      SecureRandom.hex(8)
    end

    def valid?(str)
      str.is_a?(String) && str.match?(/\A[0-9a-f]{16}\z/)
    end
  end
end
