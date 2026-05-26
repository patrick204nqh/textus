module Textus
  module Application
    module Reads
      class ValidateAll
        def initialize(ctx:)
          @ctx = ctx
        end

        def call
          @ctx.store.reader.validate_all
        end
      end
    end
  end
end
