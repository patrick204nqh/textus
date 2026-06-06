module Textus
  module Read
    # The one read path — a pure read (ADR 0089, 0093): the on-disk envelope
    # annotated with a freshness annotation. It NEVER mutates and NEVER ingests.
    # Quarantine freshness is system-pushed via `reconcile` (scheduled sweep) and
    # `hook run` (event push). Lifecycle is removed from the get path (ADR 0093):
    # intake cadence lives in `source.ttl`; GC lives in `retention:` rules; both
    # are evaluated exclusively by the `reconcile` sweep, not by a read.
    class Get
      extend Textus::Contract::DSL

      verb     :get
      summary  "Read one entry — a pure on-disk read annotated with a freshness " \
               "verdict; never ingests (quarantine freshness is reconcile + hook " \
               "only, ADR 0089). Returns the envelope (uid, etag, _meta, body, " \
               "freshness)."
      surfaces :cli, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted entry key to read, e.g. 'knowledge.project'"
      view { |v, _i| v.to_h_for_wire }

      def initialize(container:, call:, file_stat: Textus::Ports::Storage::FileStat.new)
        @container  = container
        @call       = call
        @manifest   = container.manifest
        @file_store = container.file_store
        @file_stat  = file_stat
      end

      def call(key)
        annotated_envelope(key)
      end

      # Strict variant: raises UnknownKey when the entry is missing.
      # Used by consumers (e.g. uid, Validator) that distinguish absence.
      def get(key)
        call(key) ||
          raise(UnknownKey.new(key, suggestions: @manifest.resolver.suggestions_for(key)))
      end

      private

      # Pure read; freshness is always reported as fresh (no lifecycle action at
      # read time — ADR 0093). Intake cadence and GC are reconcile-only.
      def annotated_envelope(key)
        envelope = read_raw_envelope(key)
        return nil if envelope.nil?

        annotate_fresh(envelope)
      end

      def read_raw_envelope(key)
        res = @manifest.resolver.resolve(key)
        mentry = res.entry
        path = res.path
        return nil unless @file_store.exists?(path)

        raw = @file_store.read(path)
        parsed = Entry.for_format(mentry.format).parse(raw, path: path)
        Textus::Envelope.build(
          key: key, mentry: mentry, path: path,
          meta: parsed["_meta"], body: parsed["body"],
          etag: Etag.for_bytes(raw), content: parsed["content"]
        )
      end

      def annotate_fresh(envelope)
        envelope.with(freshness: Textus::Domain::Freshness.build(
          stale: false, reason: nil, fetching: false,
        ))
      end
    end
  end
end
