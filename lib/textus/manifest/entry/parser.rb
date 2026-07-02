module Textus
  class Manifest
    class Entry
      module Parser
        def self.call(raw, root: nil)
          key = raw["key"] or raise UsageError.new("manifest entry missing key")
          lane = raw["lane"] or raise UsageError.new("manifest entry '#{key}' missing lane")

          naming = raw["naming"]
          if naming && !Textus::Protocol::V4::NAMING_PATTERNS.key?(naming)
            raise BadManifest.new("entry '#{key}': unknown naming alias '#{naming}' (known: #{Textus::Protocol::V4::NAMING_PATTERNS.keys.join(", ")})")
          end

          kind = infer_kind(key, lane, raw, root:)
          explicit_path = raw["path"]
          format = resolve_format(explicit_path)
          path   = explicit_path || derive_path(key, kind, format)

          common = {
            raw: raw,
            key: key, path: path, lane: lane,
            schema: raw["schema"], naming: naming,
            format: format,
            publish_targets: publish_targets(raw),
          }

          klass = Entry::REGISTRY[kind] or
            raise BadManifest.new("entry '#{key}': unknown inferred kind: #{kind.inspect}")
          klass.from_raw(common, raw)
        end

        def self.infer_kind(key, lane, raw, root:)
          path = raw["path"] || key.split(".").join("/")
          full_path = root ? File.join(root, "data", path) : nil

          return :nested if full_path && File.directory?(full_path)
          return :leaf if full_path && File.file?(full_path)
          return :produced if lane == "artifacts"

          :leaf
        end
        private_class_method :infer_kind

        def self.parse_source(raw, _key)
          block = raw["source"]
          return nil if block.nil?

          Textus::Manifest::Policy::Source.new(block)
        end

        def self.publish_targets(raw)
          block = raw["publish"]
          return [] if block.nil?

          unless block.is_a?(Array)
            raise BadManifest.new(
              "entry '#{raw["key"]}': `publish:` must be a list of targets " \
              "[{to:, template:?} | {tree:}] (ADR 0094); the `publish: { … }` map form was retired",
            )
          end
          block.map { |t| Textus::Manifest::Policy::PublishTarget.new(t) }
        end

        def self.resolve_format(path)
          return "markdown" if path.nil? || path.empty?

          Textus::Format.infer_from_extension(File.extname(path)) || "markdown"
        end

        def self.derive_path(key, kind_sym, format)
          dir_path = key.split(".").join("/")
          return dir_path if kind_sym == :nested

          ext = Textus::Format.for(format).extensions.first
          "#{dir_path}#{ext}"
        end

        private_class_method :derive_path
      end
    end
  end
end
