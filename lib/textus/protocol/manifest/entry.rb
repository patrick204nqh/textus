module Textus
  module Protocol
  class Manifest
    class Entry
      # Populated by each Entry::* subclass at load time.
      REGISTRY = {}
    end
  end
  end
end
