module Textus
  class Manifest
    class Entry
      module Parser
        def self.call(raw)
          key = raw["key"] or raise UsageError.new("manifest entry missing key")
          lane = raw["lane"] or raise UsageError.new("manifest entry '#{key}' missing lane")

          raw_kind = raw["kind"] or raise BadManifest.new("entry '#{key}' missing required `kind:` (#{Entry::REGISTRY.keys.join("|")})")
          kind = raw_kind.to_sym
          if %i[derived intake].include?(kind)
            raise BadManifest.new(
              "entry '#{key}': kind: #{kind} was collapsed into `kind: produced` (ADR 0095) — " \
              "the produce method is `source.from` (#{kind == :intake ? "handler" : "project|command"})",
            )
          end

          explicit_path = raw["path"]
          format = resolve_format(raw, explicit_path)
          path   = explicit_path || derive_path(key, kind, format)

          common = {
            raw: raw,
            key: key, path: path, lane: lane,
            schema: raw["schema"], owner: raw["owner"],
            format: format,
            publish_targets: publish_targets(raw)
          }

          klass = Entry::REGISTRY[kind] or
            raise BadManifest.new("entry '#{key}': unknown kind: #{kind.inspect} (known: #{Entry::REGISTRY.keys.join(", ")})")
          klass.from_raw(common, raw)
        end

        # Parse the optional `source:` block. Returns nil when absent (workflow
        # produced entries register their produce logic in .textus/workflows/).
        def self.parse_source(raw, _key)
          block = raw["source"]
          return nil if block.nil?

          Textus::Manifest::Policy::Source.new(block)
        end

        # ADR 0094: `publish:` is a LIST of target objects — to-targets
        # [{to, template?, inject_boot?}] and/or a tree-target [{tree}]. The
        # ADR-0052 map forms ({to: […]} / {tree: …}) are retired.
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

        def self.resolve_format(raw, path)
          declared = raw["format"]

          return declared || "markdown" if path.nil? || path.empty?

          ext      = File.extname(path)
          inferred = Textus::Format.infer_from_extension(ext)

          if declared.nil?
            return inferred if inferred

            return "markdown"
          end

          raise UsageError.new("entry '#{raw["key"]}': unknown format #{declared.inspect}") unless Textus::Format.formats.include?(declared)

          if ext != "" && inferred && inferred != declared
            raise UsageError.new(
              "entry '#{raw["key"]}': path extension #{ext.inspect} does not match declared format #{declared.inspect}",
            )
          end

          declared
        end

        # Derives the manifest-relative path from key + kind + format.
        # Key::Path.normalize_relative_path will prepend data/ at resolution time.
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
