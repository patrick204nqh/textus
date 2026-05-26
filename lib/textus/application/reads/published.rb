module Textus
  module Application
    module Reads
      class Published
        def initialize(ctx:)
          @ctx = ctx
        end

        def call
          Dependencies.published_of(@ctx.manifest)
        end
      end
    end
  end
end
