module Textus
  module Protocol
    module Handlers
      module Concern
        def self.included(base)
          base.extend(self)
        end

        def ok(payload) = payload

        def not_found(key)
          raise Textus::UnknownKey.new(key)
        end

        def stale_etag(key, expected, actual)
          raise Textus::EtagMismatch.new(key, expected, actual)
        end
      end
    end
  end
end
