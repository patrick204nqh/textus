module Textus
  module Application
    module Reads
      class Deps
        def initialize(manifest:)
          @manifest = manifest
        end

        def call(key)
          Dependencies.deps_of(@manifest, key)
        end
      end
    end
  end
end
