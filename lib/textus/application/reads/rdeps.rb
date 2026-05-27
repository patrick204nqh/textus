module Textus
  module Application
    module Reads
      class Rdeps
        def initialize(manifest:)
          @manifest = manifest
        end

        def call(key)
          Dependencies.rdeps_of(@manifest, key)
        end
      end
    end
  end
end
