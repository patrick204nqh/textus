module Textus
  class Manifest
    class Entry
      # A directory entry: enumerates a tree of leaves and resolves to one
      # publish mode (ADR 0049). The publish algorithms themselves live in
      # Entry::Publish::* — Nested is just the value (attributes + ignore
      # predicate) those modes read.
      class Nested < Base
        attr_reader :index_filename, :publish_tree, :ignore

        def initialize(index_filename: nil, publish_tree: nil, ignore: nil, **rest)
          super(**rest)
          @index_filename = index_filename
          @publish_tree = publish_tree
          @ignore = Array(ignore)
        end

        def nested? = true

        # True when `rel_path` (slash-joined, relative to the entry base) matches
        # any configured ignore glob. Evaluated ABOVE key-legality (ADR 0042):
        # an ignored path is excluded, never judged.
        def ignored?(rel_path) = IgnoreMatcher.match?(@ignore, rel_path)

        KIND = :nested

        def self.from_raw(common, raw)
          new(
            index_filename: raw["index_filename"],
            publish_tree: raw["publish_tree"],
            ignore: raw["ignore"],
            **common,
          )
        end

        Entry::REGISTRY[KIND] = self
      end
    end
  end
end
