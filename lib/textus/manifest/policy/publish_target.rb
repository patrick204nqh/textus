module Textus
  class Manifest
    class Policy
      # One publish destination (ADR 0094). Exactly one of:
      #   to-target   { to:, template:?, inject_boot:? }  — render data through a
      #               template, or copy verbatim when no template
      #   tree-target { tree: }                           — ADR 0052 subtree mirror
      # Provenance is NOT a publish flag — it lives in the data's `_meta`.
      class PublishTarget
        attr_reader :to, :tree, :template, :inject_boot

        def initialize(raw)
          if raw.key?("provenance")
            raise Textus::BadManifest.new("publish `provenance:` was removed (ADR 0094): provenance lives in the data's `_meta`")
          end

          @to   = raw["to"]
          @tree = raw["tree"]
          raise Textus::BadManifest.new("a publish target needs exactly one of `to:` or `tree:`") unless @to.nil? ^ @tree.nil?

          @template    = raw["template"]
          @inject_boot = raw["inject_boot"] == true
          return unless tree_target? && (@template || @inject_boot)

          raise Textus::BadManifest.new("a tree target takes no template/inject_boot (ADR 0094)")
        end

        def to_target?   = !@to.nil?
        def tree_target? = !@tree.nil?
        def renders?     = to_target? && !@template.nil?
      end
    end
  end
end
