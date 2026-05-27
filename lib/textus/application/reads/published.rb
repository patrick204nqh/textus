module Textus
  module Application
    module Reads
      class Published
        def initialize(manifest:)
          @manifest = manifest
        end

        def call
          Dependencies.published_of(@manifest)
        end
      end
    end
  end
end
