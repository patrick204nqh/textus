module Textus
  class Manifest
    class Entry
      class Leaf < Base
        KIND = :leaf

        def leaf? = true

        def self.from_raw(common, _raw)
          new(**common)
        end

        Entry::REGISTRY[KIND] = self
      end
    end
  end
end
