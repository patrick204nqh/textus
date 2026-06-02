module Textus
  class Manifest
    class Entry
      module Validators
        module PublishTree
          # Reuse PublishEach's var regex — a publish_tree target must be a plain
          # path, so ANY template var is an error.
          VAR_RE = Validators::PublishEach::VAR_RE

          def self.call(entry, policy: nil) # rubocop:disable Lint/UnusedMethodArgument
            # Use raw to detect misuse on non-nested entries (typed attr stubs nil on Base).
            publish_tree = entry.nested? ? entry.publish_tree : entry.raw["publish_tree"]
            return if publish_tree.nil?

            raise UsageError.new("entry '#{entry.key}': publish_tree requires nested: true") unless entry.nested?
            raise UsageError.new("entry '#{entry.key}': publish_tree must be a string") unless publish_tree.is_a?(String)

            unless Array(entry.publish_to).empty?
              raise UsageError.new("entry '#{entry.key}': publish_to and publish_tree are mutually exclusive")
            end
            unless entry.publish_each.nil?
              raise UsageError.new("entry '#{entry.key}': publish_each and publish_tree are mutually exclusive")
            end
            unless entry.index_filename.nil?
              raise UsageError.new(
                "entry '#{entry.key}': index_filename and publish_tree are mutually exclusive — " \
                "publish_tree mirrors a whole subtree by path and never enumerates an index.",
              )
            end

            used_vars = publish_tree.scan(VAR_RE).flatten
            return if used_vars.empty?

            raise UsageError.new(
              "entry '#{entry.key}': publish_tree names a single directory and takes no template variable(s) " \
              "#{used_vars.map { |v| "{#{v}}" }.join(", ")} — it mirrors the whole subtree to one target dir.",
            )
          end
        end
      end
    end
  end
end
