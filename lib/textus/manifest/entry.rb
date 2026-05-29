module Textus
  class Manifest
    class Entry
      # Populated by each Entry::* subclass at load time.
      REGISTRY = {}
    end
  end
end
