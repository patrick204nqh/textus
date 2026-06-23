module Textus
  class Manifest
    class Policy
      module Predicates
        class FreshWithin
          def self.call(manifest:, actor:, action:, key:, schemas: nil, envelope: nil, extra: {})
            { pass: true }
          end
        end
      end
    end
  end
end
