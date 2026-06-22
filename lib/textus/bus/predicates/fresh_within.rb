module Textus
  module Bus
    module Predicates
      class FreshWithin
        def self.call(manifest:, schemas: nil, actor:, action:, key:, envelope: nil, extra: {})
          { pass: true }
        end
      end
    end
  end
end
