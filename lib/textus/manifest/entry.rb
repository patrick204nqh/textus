module Textus
  class Manifest
    class Entry
      # Re-exported for backward compatibility with callers that referenced these
      # constants on Entry. Canonical source is the PublishEach validator.
      PUBLISH_EACH_VARS = Validators::PublishEach::KNOWN_VARS
      PUBLISH_EACH_VAR_RE = Validators::PublishEach::VAR_RE

      # Populated by each Entry::* subclass at load time.
      REGISTRY = {}
    end
  end
end
