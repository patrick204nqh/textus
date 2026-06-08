module Textus
  module Domain
    module Policy
      # An entry's data-acquisition declaration (ADR 0094). `source:` says HOW the
      # entry's data is acquired; rendering is a publish concern, so there are no
      # template/render fields here. `from` is the acquire + staleness axis:
      #   from: project -> derived  (internal projection; observable -> rdeps staleness)
      #   from: handler -> intake   (external fetch; unobservable -> ttl staleness)
      #   from: command -> external (out-of-band runner; staleness only, textus never runs it)
      # Materialization is async-only (job-queue model): a write enqueues a
      # `materialize` job, converged by a worker. There is no per-entry write
      # trigger knob.
      class Source
        FROMS = %w[project handler command].freeze

        attr_reader :from, :handler, :config, :command, :sources

        def initialize(raw)
          @from = raw["from"].to_s
          unless FROMS.include?(@from)
            raise Textus::BadManifest.new("source.from must be one of #{FROMS.join("|")}, got #{raw["from"].inspect}")
          end

          @ttl = raw["ttl"]
          @projection = {}

          case @from
          when "project" then init_project(raw)
          when "handler" then init_handler(raw)
          when "command" then init_command(raw)
          end
        end

        def kind        = @from == "handler" ? :intake : :derived
        def external?   = @from == "command"
        def projection? = @from == "project"
        def ttl_seconds = @ttl.nil? ? nil : Textus::Domain::Duration.seconds(@ttl)

        # Flattened projection accessors (ADR 0094) — read directly off the source
        # block; nil when absent or not a projection source.
        def select    = @projection["select"]
        def pluck     = @projection["pluck"]
        def sort_by   = @projection["sort_by"]
        def transform = @projection["transform"]

        # The projection spec hash fed to Textus::Projection (string keys, only the
        # present fields). {} when not a projection.
        def projection_spec = @projection.dup

        private

        def init_project(raw)
          %w[select pluck sort_by transform].each { |f| @projection[f] = raw[f] if raw.key?(f) }
          return unless @projection["select"].nil? && @projection["transform"].nil?

          raise Textus::BadManifest.new("source (from: project) requires `select:` and/or `transform:`")
        end

        def init_handler(raw)
          @handler = raw["handler"] or
            raise Textus::BadManifest.new("source (from: handler) requires a `handler:` field")
          @config = raw["config"] || {}
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
