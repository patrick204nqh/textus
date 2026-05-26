module Textus
  module Application
    module Reads
      class Uid
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(key)
          @ctx.store.reader.uid(key)
        end
      end
    end
  end
end
