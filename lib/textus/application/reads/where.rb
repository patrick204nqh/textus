module Textus
  module Application
    module Reads
      class Where
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(key)
          @ctx.store.reader.where(key)
        end
      end
    end
  end
end
