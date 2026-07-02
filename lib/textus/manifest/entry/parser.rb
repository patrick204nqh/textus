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

          kind = infer_kind(key, raw, root:)
          explicit_path = raw["path"]
          format = resolve_format(key, kind, root, raw["format"], explicit_path)
          path = explicit_path || derive_path(key, kind, format)

          common = {
            raw: raw,
            key: key, path: path, lane: lane,
            format: format, naming: naming,
            schema: raw["schema"],
          }

          klass = Entry::REGISTRY[kind]
          raise BadManifest.new("entry '#{key}': unknown inferred kind: #{kind.inspect}") unless klass

          klass.from_raw(common, raw)
        end

        def self.infer_kind(key, raw, root:)
          base = raw["path"] || key.split(".").join("/")
          dir = root ? File.join(root, "data", base) : nil

          return :nested if dir && File.directory?(dir)
          return :leaf if dir && Dir.glob("#{dir}.*").any? { |p| File.file?(p) }

          :leaf
        end
        private_class_method :infer_kind

        def self.resolve_format(key, kind, root, declared, explicit_path)
          return "markdown" if kind == :nested

          if explicit_path
            return Textus::Format.infer_from_extension(File.extname(explicit_path)) || declared || "markdown"
          end

          dir = root ? File.join(root, "data", key.split(".").join("/")) : nil
          if dir
            existing = Dir.glob("#{dir}.*").find { |p| File.file?(p) }
            return Textus::Format.infer_from_extension(File.extname(existing)) if existing
          end

          declared || "markdown"
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
