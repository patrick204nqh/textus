module Textus
  class Manifest
    class Entry
      class Nested < Base
        def nested? = true

        KIND = :nested

        def self.from_raw(common, _raw)
          new(**common)
        end

        Entry::REGISTRY[KIND] = self
      end
    end
  end
end
