module Textus
  module Application
    module Reads
      class Published
        def initialize(ctx:)
          @ctx = ctx
        end

        def call
          @ctx.store.reader.published
        end
      end
    end
  end
end
