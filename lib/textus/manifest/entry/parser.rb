module Textus
  class Manifest
    class Entry
      module Parser
        COMPUTE_KINDS = %w[projection external].freeze

        def self.call(raw)
          key = raw["key"] or raise UsageError.new("manifest entry missing key")
          path = raw["path"] or raise UsageError.new("manifest entry '#{key}' missing path")
          zone = raw["zone"] or raise UsageError.new("manifest entry '#{key}' missing zone")

          raw_kind = raw["kind"] or raise BadManifest.new("entry '#{key}' missing required `kind:` (#{Entry::REGISTRY.keys.join("|")})")
          kind = raw_kind.to_sym
          format = resolve_format(raw, path)

          common = {
            raw: raw,
            key: key, path: path, zone: zone,
            schema: raw["schema"], owner: raw["owner"],
            format: format,
            # ADR 0052: publish config is one typed block; the internal
            # publish_to/publish_tree readers (the ADR 0049 modes) are sourced
            # from it (publish_to <- publish.to, publish_tree <- publish.tree).
            publish_to: raw.dig("publish", "to")
          }

          klass = Entry::REGISTRY[kind] or
            raise BadManifest.new("entry '#{key}': unknown kind: #{kind.inspect} (known: #{Entry::REGISTRY.keys.join(", ")})")
          klass.from_raw(common, raw)
        end

        def self.parse_source(raw, key)
          compute = raw["compute"]
          raise BadManifest.new("derived entry '#{key}' requires compute: { kind: projection|external } or template:") if compute.nil?

          unless COMPUTE_KINDS.include?(compute["kind"])
            raise BadManifest.new(
              "entry '#{key}': compute.kind must be one of #{COMPUTE_KINDS.join(", ")} (got #{compute["kind"].inspect})",
            )
          end

          if compute["kind"] == "projection"
            Entry::Derived::Projection.new(
              select: compute["select"],
              pluck: compute["pluck"],
              sort_by: compute["sort_by"],
              transform: compute["transform"],
            )
          else
            Entry::Derived::External.new(sources: compute["sources"], command: compute["command"])
          end
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
