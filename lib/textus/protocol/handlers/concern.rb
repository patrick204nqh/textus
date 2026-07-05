module Textus
  module Protocol
    module Handlers
      module Concern
        def self.included(base)
          base.extend(self)
        end
      end
    end
  end
end
