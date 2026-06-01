module Textus
  class Manifest
    class Entry
      module Validators
        module PublishEach
          KNOWN_VARS = %w[leaf basename key ext].freeze
          VAR_RE = /\{([a-z]+)\}/
          REQUIRED_DISCRIMINATOR_VARS = %w[leaf basename key].freeze

          def self.call(entry, policy: nil) # rubocop:disable Lint/UnusedMethodArgument
            # Use raw to detect misuse on non-nested entries (typed attr stubs nil on Base).
            publish_each = entry.nested? ? entry.publish_each : entry.raw["publish_each"]
            return if publish_each.nil?

            raise UsageError.new("entry '#{entry.key}': publish_each requires nested: true") unless entry.nested?

            publish_to = entry.publish_to
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

            validate_discriminator(entry, used_vars, publish_each)
          end

          def self.validate_discriminator(entry, used_vars, publish_each)
            if entry.index_filename
              forbidden = used_vars & %w[basename ext]
              unless forbidden.empty?
                raise UsageError.new(
                  "entry '#{entry.key}': publish_each names a directory " \
                  "(index_filename: '#{entry.index_filename}'); {basename}/{ext} are file-only — " \
                  "use {leaf} or {key}.",
                )
              end
              last_segment = publish_each.sub(%r{/\z}, "").split("/").last
              if last_segment == entry.index_filename
                raise UsageError.new(
                  "entry '#{entry.key}': directory-leaf publish_each must name the target DIRECTORY, " \
                  "not the index file — drop the trailing '/#{entry.index_filename}' " \
                  "(the whole leaf subtree is copied into the named directory).",
                )
              end
              ext = File.extname(last_segment)
              unless ext.empty?
                raise UsageError.new(
                  "entry '#{entry.key}': directory-leaf publish_each names a DIRECTORY target, but its " \
                  "final segment '#{last_segment}' looks like a file (extension '#{ext}') — " \
                  "drop the extension (the whole leaf subtree is copied into the named directory).",
                )
              end
              return if used_vars.intersect?(%w[leaf key])

              raise UsageError.new(
                "entry '#{entry.key}': directory-leaf publish_each must reference {leaf} or {key} " \
                "(else every leaf would clobber the same directory).",
              )
            end

            return if used_vars.intersect?(REQUIRED_DISCRIMINATOR_VARS)

            raise UsageError.new(
              "entry '#{entry.key}': publish_each must reference at least one of {leaf}, {basename}, or {key} " \
              "(else every leaf would clobber the same target).",
            )
          end
          private_class_method :validate_discriminator
        end
      end
    end
  end
end
