module Textus
  module Bus
    module Predicates
      class EtagMatch
        def self.call(manifest:, schemas: nil, actor:, action:, key:, envelope: nil, extra: {})
          if_etag = extra[:if_etag]
          return { pass: true } if if_etag.nil?

          current = envelope&.etag
          pass = current.nil? || current == if_etag
          { pass:, error: pass ? nil : Textus::EtagMismatch.new(key, if_etag, current) }
        end
      end
    end
  end
end
