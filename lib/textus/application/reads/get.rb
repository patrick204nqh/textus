module Textus
  module Application
    module Reads
      # Pure read: returns the on-disk envelope annotated with a freshness
      # verdict. Never triggers refresh; never invokes the orchestrator.
      #
      # For interactive reads that want refresh-on-stale, use
      # `Reads::GetOrRefresh`, which composes this with the orchestrator.
      class Get
        def initialize(ctx:, evaluator: Textus::Domain::Freshness::Evaluator)
          @ctx       = ctx
          @evaluator = evaluator
        end

        def call(key)
          envelope = read_raw_envelope(key)
          return nil if envelope.nil?

          policy_set = @ctx.manifest.rules_for(key)
          refresh_policy = policy_set.refresh
          return annotate_fresh(envelope) if refresh_policy.nil?

          policy = refresh_policy.to_freshness_policy
          verdict = @evaluator.call(policy, envelope, now: @ctx.now)

          envelope.with(freshness: Textus::Domain::Freshness.build(
            stale: verdict.stale?,
            reason: verdict.reason,
            refreshing: false,
          ))
        end

        # Strict variant: raises UnknownKey when the entry is missing.
        # Used by consumers (e.g. Validator) that need to distinguish absence
        # from emptiness.
        def get(key)
          call(key) || raise(UnknownKey.new(key, suggestions: @ctx.manifest.suggestions_for(key)))
        end

        private

        def read_raw_envelope(key)
          res = @ctx.manifest.resolve(key)
          mentry = res.entry
          path = res.path
          return nil unless @ctx.file_store.exists?(path)

          raw = @ctx.file_store.read(path)
          parsed = Entry.for_format(mentry.format).parse(raw, path: path)
          Envelope.build(
            key: key, mentry: mentry, path: path,
            meta: parsed["_meta"], body: parsed["body"],
            etag: Etag.for_bytes(raw), content: parsed["content"]
          )
        end

        def annotate_fresh(envelope)
          envelope.with(freshness: Textus::Domain::Freshness.build(
            stale: false, reason: nil, refreshing: false,
          ))
        end
      end
    end
  end
end
