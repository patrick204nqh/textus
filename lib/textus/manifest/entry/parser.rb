module Textus
  class Manifest
    class Entry
      module Parser
        COMPUTE_KINDS = %w[projection external].freeze

        def self.call(manifest, raw)
          key = raw["key"] or raise UsageError.new("manifest entry missing key")
          path = raw["path"] or raise UsageError.new("manifest entry '#{key}' missing path")
          zone = raw["zone"] or raise UsageError.new("manifest entry '#{key}' missing zone")

          raw_kind = raw["kind"] or raise BadManifest.new("entry '#{key}' missing required `kind:` (leaf|nested|derived|intake)")
          kind = raw_kind.to_sym
          format = resolve_format(raw, path)

          common = {
            manifest: manifest, raw: raw,
            key: key, path: path, zone: zone,
            schema: raw["schema"], owner: raw["owner"],
            format: format
          }

          case kind
          when :leaf    then build_leaf(common, raw)
          when :nested  then build_nested(common, raw)
          when :derived then build_derived(common, raw, key)
          when :intake  then build_intake(common, raw, key)
          else raise BadManifest.new("entry '#{key}': unknown kind: #{kind.inspect}")
          end
        end

        def self.build_leaf(common, raw)
          Leaf.new(publish_to: raw["publish_to"], **common)
        end

        def self.build_nested(common, raw)
          Nested.new(
            index_filename: raw["index_filename"],
            publish_each: raw["publish_each"],
            publish_to: raw["publish_to"],
            **common,
          )
        end

        def self.build_derived(common, raw, key)
          source = parse_source(raw, key)
          Derived.new(
            source: source,
            template: raw["template"],
            inject_boot: raw["inject_boot"] == true,
            publish_to: raw["publish_to"],
            events: raw["events"] || {},
            **common,
          )
        end

        def self.build_intake(common, raw, key)
          intake = raw["intake"] || {}
          handler = intake["handler"] || raw["intake_handler"] or
            raise UsageError.new("intake entry '#{key}' missing handler")
          config = intake["config"] || raw["intake_config"] || {}
          Intake.new(handler: handler, config: config, events: raw["events"] || {}, **common)
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
            Derived::Projection.new(
              select: compute["select"],
              pluck: compute["pluck"],
              sort_by: compute["sort_by"],
              transform: compute["transform"],
            )
          else
            Derived::External.new(sources: compute["sources"], runner: compute["runner"])
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
