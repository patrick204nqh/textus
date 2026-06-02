module Textus
  class Manifest
    class Entry
      module Publish
        # The publish_each template vocabulary. A publish_each value is a path
        # with `{leaf}`, `{basename}`, `{key}`, `{ext}` placeholders; a
        # publish_tree value must be a plain path (any var is an error), so the
        # modes reuse VAR_RE to detect stray vars there too.
        module Template
          KNOWN_VARS = %w[leaf basename key ext].freeze
          VAR_RE = /\{([a-z]+)\}/
          REQUIRED_DISCRIMINATOR_VARS = %w[leaf basename key].freeze

          # Substitute `{var}` placeholders from a string-keyed hash.
          def self.expand(template, vars)
            template.gsub(VAR_RE) { vars.fetch(::Regexp.last_match(1)) }
          end
        end
      end
    end
  end
end
