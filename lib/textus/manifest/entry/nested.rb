module Textus
  class Manifest
    class Entry
      # A directory entry: enumerates a tree of leaves and resolves to one
      # publish mode (ADR 0049). The publish algorithms themselves live in
      # Entry::Publish::* — Nested is just the value (attributes + ignore
      # predicate) those modes read.
      class Nested < Base
        attr_reader :ignore

        def initialize(ignore: nil, **rest)
          super(**rest)
          @ignore = Array(ignore)
        end

        def nested? = true

        # True when `rel_path` (slash-joined, relative to the entry base) matches
        # any configured ignore glob. Evaluated ABOVE key-legality (ADR 0042):
        # an ignored path is excluded, never judged.
        def ignored?(rel_path) = IgnoreMatcher.match?(@ignore, rel_path)

        KIND = :nested

        def self.from_raw(common, raw)
          # publish_tree is derived from publish_targets (ADR 0094) via Base#publish_tree
          new(
            ignore: raw["ignore"],
            **common,
          )
        end

        Entry::REGISTRY[KIND] = self
      end
    end
  end
end
