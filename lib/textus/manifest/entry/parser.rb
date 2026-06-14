module Textus
  class Manifest
    class Entry
      module Parser
        def self.call(raw)
          key = raw["key"] or raise UsageError.new("manifest entry missing key")
          path = raw["path"] or raise UsageError.new("manifest entry '#{key}' missing path")
          lane = raw["lane"] or raise UsageError.new("manifest entry '#{key}' missing lane")

          raw_kind = raw["kind"] or raise BadManifest.new("entry '#{key}' missing required `kind:` (#{Entry::REGISTRY.keys.join("|")})")
          kind = raw_kind.to_sym
          if %i[derived intake].include?(kind)
            raise BadManifest.new(
              "entry '#{key}': kind: #{kind} was collapsed into `kind: produced` (ADR 0095) — " \
              "the produce method is `source.from` (#{kind == :intake ? "handler" : "project|command"})",
            )
          end
          format = resolve_format(raw, path)

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

        # ADR 0093: an entry's production block is the unified `source:`. Returns a
        # Manifest::Policy::Source; kind (intake/derived) is read from source.from.
        def self.parse_source(raw, key)
          block = raw["source"] or
            raise BadManifest.new("entry '#{key}' requires a source: { from: derive|fetch|external, ... }")

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
          ext = File.extname(path)
          inferred = Textus::Entry.infer_from_extension(ext)

          if declared.nil?
            return inferred if inferred

            return "markdown"
          end

          raise UsageError.new("entry '#{raw["key"]}': unknown format #{declared.inspect}") unless Textus::Entry.formats.include?(declared)

          if ext != "" && inferred && inferred != declared
            raise UsageError.new(
              "entry '#{raw["key"]}': path extension #{ext.inspect} does not match declared format #{declared.inspect}",
            )
          end

          declared
        end
      end
    end
  end
end
