module Textus
  module Protocol
    module Handlers
      module Concern
        def self.included(base)
          base.extend(self)
        end

        def response(**fields)
          { "protocol" => Textus::PROTOCOL, **fields.transform_keys(&:to_s) }
        end
      end
    end
  end
end
