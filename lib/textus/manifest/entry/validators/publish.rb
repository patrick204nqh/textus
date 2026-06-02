module Textus
  class Manifest
    class Entry
      module Validators
        # ADR 0049: one publish validator. Exclusivity among the publish keys is
        # enforced structurally by Publish.resolve (reached via #publish_mode),
        # and each mode's shape rules run *because that mode resolved* — replacing
        # the four scattered pairwise "not-both" guards of the old PublishEach +
        # PublishTree validators. Misuse on a non-nested entry is still caught
        # here from raw, since the typed attrs stub nil on Base.
        module Publish
          def self.call(entry, policy: nil) # rubocop:disable Lint/UnusedMethodArgument
            unless entry.nested?
              %w[publish_each publish_tree].each do |key|
                raise UsageError.new("entry '#{entry.key}': #{key} requires nested: true") if entry.raw[key]
              end
              return
            end

            entry.publish_mode.validate!
          end
        end
      end
    end
  end
end
