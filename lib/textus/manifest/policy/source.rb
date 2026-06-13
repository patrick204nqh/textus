module Textus
  class Manifest
    class Policy
      # An entry's data-acquisition declaration (ADR 0094). `source:` says HOW the
      # entry's data is acquired; rendering is a publish concern, so there are no
      # template/render fields here. `from` is the acquire + staleness axis:
      #   from: derive -> derived   (internal projection; observable -> rdeps staleness)
      #   from: fetch -> intake     (external fetch; unobservable -> ttl staleness)
      #   from: external -> external (out-of-band runner; staleness only, textus never runs it)
      # Materialization is async-only (job-queue model): a write enqueues a
      # `materialize` job, converged by a worker. There is no per-entry write
      # trigger knob.
      class Source
        FROMS = %w[fetch derive external].freeze

        attr_reader :from, :handler, :config, :command, :sources

        def initialize(raw)
          @from = raw["from"].to_s
          unless FROMS.include?(@from)
            raise Textus::BadManifest.new("source.from must be one of #{FROMS.join("|")}, got #{raw["from"].inspect}")
          end

          @ttl = raw["ttl"]
          @projection = {}

          case @from
          when "fetch" then init_fetch(raw)
          when "derive" then init_derive(raw)
          when "external" then init_external(raw)
          end
        end

        def kind
          { "fetch" => :intake, "derive" => :derived, "external" => :external }.fetch(@from)
        end

        def fetch?      = @from == "fetch"
        def derive?     = @from == "derive"
        def external?   = @from == "external"
        def projection? = derive?
        def ttl_seconds = @ttl.nil? ? nil : Textus::Core::Duration.seconds(@ttl)

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

        def init_derive(raw)
          %w[select pluck sort_by transform].each { |f| @projection[f] = raw[f] if raw.key?(f) }
          return unless @projection["select"].nil? && @projection["transform"].nil?

          raise Textus::BadManifest.new("source (from: derive) requires `select:` and/or `transform:`")
        end

        def init_fetch(raw)
          @handler = raw["handler"] or
            raise Textus::BadManifest.new("source (from: fetch) requires a `handler:` field")
          @config = raw["config"] || {}
        end

        def init_external(raw)
          @command = raw["command"] or
            raise Textus::BadManifest.new("source (from: external) requires a `command:` field")
          @sources = raw["sources"] || []
        end
      end
    end
  end
end
