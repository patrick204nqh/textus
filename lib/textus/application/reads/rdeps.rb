module Textus
  module Application
    module Reads
      class Rdeps
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(key)
          Dependencies.rdeps_of(@ctx.manifest, key)
        end
      end
    end
  end
end
