module Textus
  module Application
    module Reads
      class Deps
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(key)
          @ctx.store.reader.deps(key)
        end
      end
    end
  end
end
