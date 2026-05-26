module Textus
  class Manifest
    class Entry
      module Parser
        COMPUTE_KINDS = %w[projection external].freeze

        def self.call(manifest, raw)
          key = raw["key"] or raise UsageError.new("manifest entry missing key")
          path = raw["path"] or raise UsageError.new("manifest entry '#{key}' missing path")
          zone = raw["zone"] or raise UsageError.new("manifest entry '#{key}' missing zone")

          nested = raw["nested"] == true
          compute, projection, generator = parse_compute(raw, key)
          intake_handler, intake_config = parse_intake(raw["intake"])
          format = resolve_format(raw, path, nested)

          Textus::Manifest::Entry.new(
            manifest: manifest, raw: raw,
            key: key, path: path, zone: zone,
            schema: raw["schema"], owner: raw["owner"],
            nested: nested,
            template: raw["template"],
            publish_to: Array(raw["publish_to"]),
            publish_each: raw["publish_each"],
            events: raw["events"] || {},
            inject_intro: raw["inject_intro"] == true,
            index_filename: raw["index_filename"],
            format: format,
            compute: compute, projection: projection, generator: generator,
            intake_handler: intake_handler, intake_config: intake_config
          )
        end

        def self.parse_compute(raw, key)
          src = raw["compute"]
          return [nil, nil, nil] if src.nil?

          kind = src["kind"]
          unless COMPUTE_KINDS.include?(kind)
            raise BadManifest.new(
              "entry '#{key}': compute.kind must be one of #{COMPUTE_KINDS.join(", ")} (got #{kind.inspect})",
            )
          end

          frozen = src.freeze
          if kind == "projection"
            [frozen, frozen, nil]
          else
            [frozen, nil, frozen]
          end
        end

        def self.parse_intake(src)
          src ||= {}
          [src["handler"], src["config"] || {}]
        end

        def self.resolve_format(raw, path, nested)
          declared = raw["format"]
          ext = File.extname(path)
          inferred = Textus::Entry.infer_from_extension(ext)

          if declared.nil?
            return inferred if inferred
            return "markdown" if ext == "" && nested
            return "markdown" if ext == ""

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
