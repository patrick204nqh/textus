module Textus
  class Manifest
    class Entry
      module Publish
        # An entry with no publish_* key — nothing to publish.
        class None < Mode
          def publish(_pctx, prefix: nil) # rubocop:disable Lint/UnusedMethodArgument
            nil
          end
        end
      end
    end
  end
end
