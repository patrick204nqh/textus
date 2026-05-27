module Textus
  class Manifest
    class Entry
      class Leaf < Base
        attr_reader :publish_to

        def initialize(publish_to: [], **rest)
          super(**rest)
          @publish_to = Array(publish_to)
        end

        def leaf? = true
      end
    end
  end
end
