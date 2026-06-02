module Textus
  class Manifest
    class Entry
      module Publish
        # Template-variable detection for publish targets. The only surviving
        # use after ADR 0051 (which removed publish_each and its `{leaf}`/
        # `{basename}`/`{key}`/`{ext}` vocabulary) is Tree.validate!, which uses
        # VAR_RE to reject any `{var}` in a publish_tree value — that key names a
        # single directory by plain path and interprets no variables.
        module Template
          VAR_RE = /\{([a-z]+)\}/
        end
      end
    end
  end
end
