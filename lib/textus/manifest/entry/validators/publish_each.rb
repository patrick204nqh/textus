module Textus
  class Manifest
    class Entry
      module Validators
        module PublishEach
          KNOWN_VARS = %w[leaf basename key ext].freeze
          VAR_RE = /\{([a-z]+)\}/
          REQUIRED_DISCRIMINATOR_VARS = %w[leaf basename key].freeze

          def self.call(entry) # rubocop:disable Metrics/AbcSize
            publish_each = entry.respond_to?(:publish_each) ? entry.publish_each : entry.raw["publish_each"]
            return if publish_each.nil?

            raise UsageError.new("entry '#{entry.key}': publish_each requires nested: true") unless entry.nested?

            publish_to = entry.respond_to?(:publish_to) ? entry.publish_to : Array(entry.raw["publish_to"])
            raise UsageError.new("entry '#{entry.key}': publish_to and publish_each are mutually exclusive") unless publish_to.empty?
            raise UsageError.new("entry '#{entry.key}': publish_each must be a string") unless publish_each.is_a?(String)

            used_vars = publish_each.scan(VAR_RE).flatten
            unknown = used_vars - KNOWN_VARS
            unless unknown.empty?
              raise UsageError.new(
                "entry '#{entry.key}': publish_each uses unknown template variable(s) " \
                "#{unknown.map { |v| "{#{v}}" }.join(", ")}. Known: #{KNOWN_VARS.map { |v| "{#{v}}" }.join(", ")}.",
              )
            end

            return if used_vars.any? { |v| REQUIRED_DISCRIMINATOR_VARS.include?(v) }

            raise UsageError.new(
              "entry '#{entry.key}': publish_each must reference at least one of {leaf}, {basename}, or {key} " \
              "(else every leaf would clobber the same target).",
            )
          end
        end
      end
    end
  end
end
