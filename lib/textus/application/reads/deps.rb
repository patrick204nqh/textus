module Textus
  module Application
    module Reads
      class Deps
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(key)
          Dependencies.deps_of(@ctx.manifest, key)
        end
      end
    end
  end
end
