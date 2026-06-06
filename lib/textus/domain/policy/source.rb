module Textus
  module Domain
    module Policy
      # An entry's production declaration (ADR 0093). Unifies the former
      # `intake:` block and the derived `compute:`/`template:` blocks into one
      # `source:` field: the entry's bytes are PRODUCED from upstream, and the
      # only difference between the kinds is the staleness signal —
      #   from: handler  -> intake  (upstream UNOBSERVABLE; staleness = ttl proxy)
      #   from: template -> derived (upstream OBSERVABLE; staleness = rdeps)
      #   from: command  -> derived/external (out-of-band runner; staleness only)
      # `on_write` (sync|async, default async) is the write-trigger strategy for
      # observable (template) sources; it is meaningless for intake.
      class Source
        FROMS      = %w[handler template command].freeze
        STRATEGIES = %w[async sync].freeze

        attr_reader :from, :handler, :config, :template, :project,
                    :command, :sources, :inject_boot, :provenance

        def initialize(raw)
          @from = raw["from"].to_s
          unless FROMS.include?(@from)
            raise Textus::BadManifest.new("source.from must be one of #{FROMS.join("|")}, got #{raw["from"].inspect}")
          end

          @on_write = (raw["on_write"] || "async").to_s
          unless STRATEGIES.include?(@on_write)
            raise Textus::BadManifest.new("source.on_write must be one of #{STRATEGIES.join("/")}, got #{@on_write.inspect}")
          end

          @ttl         = raw["ttl"]
          @inject_boot = raw["inject_boot"] == true
          @provenance  = raw.fetch("provenance", true) != false

          case @from
          when "handler"  then init_handler(raw)
          when "template" then init_template(raw)
          when "command"  then init_command(raw)
          end
        end

        def kind        = @from == "handler" ? :intake : :derived
        def external?   = @from == "command"
        def projection? = @from == "template"
        def sync?       = @on_write == "sync"
        def ttl_seconds = @ttl.nil? ? nil : Textus::Domain::Duration.seconds(@ttl)

        # Projection field accessors (ADR 0093) — mirror the old
        # Derived::Projection Data surface so the builder/renderers read them
        # uniformly off a Policy::Source. nil when this is not a template source
        # or the field is absent.
        def select    = project_field("select")
        def pluck     = project_field("pluck")
        def sort_by   = project_field("sort_by")
        def transform = project_field("transform")

        # The projection spec hash the builder feeds to Textus::Projection
        # (string keys, the four projection fields). {} when no projection.
        def projection_spec = @project || {}

        private

        def project_field(key) = @project && @project[key]

        def init_handler(raw)
          @handler = raw["handler"] or
            raise Textus::BadManifest.new("source (from: handler) requires a `handler:` field")
          @config = raw["config"] || {}
        end

        def init_template(raw)
          @template = raw["template"] or
            raise Textus::BadManifest.new("source (from: template) requires a `template:` field")
          @project = raw["project"]
        end

        def init_command(raw)
          @command = raw["command"] or
            raise Textus::BadManifest.new("source (from: command) requires a `command:` field")
          @sources = raw["sources"] || []
        end
      end
    end
  end
end
