module Textus
  module Application
    module Reads
      class Rdeps
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(key)
          @ctx.store.reader.rdeps(key)
        end
      end
    end
  end
end
