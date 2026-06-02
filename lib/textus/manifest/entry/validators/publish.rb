module Textus
  class Manifest
    class Entry
      module Validators
        # ADR 0049: one publish validator. Exclusivity among the publish keys is
        # enforced structurally by Publish.resolve (reached via #publish_mode),
        # and each mode's shape rules run *because that mode resolved* — replacing
        # the scattered pairwise "not-both" guards of the old PublishEach +
        # PublishTree validators. Misuse on a non-nested entry is still caught
        # here from raw, since the typed attrs stub nil on Base. (publish_each was
        # removed in 0.42.0 — ADR 0051; Schema rejects it at load.)
        module Publish
          def self.call(entry, policy: nil) # rubocop:disable Lint/UnusedMethodArgument
            unless entry.nested?
              raise UsageError.new("entry '#{entry.key}': publish_tree requires nested: true") if entry.raw["publish_tree"]

              return
            end

            entry.publish_mode.validate!
          end
        end
      end
    end
  end
end
