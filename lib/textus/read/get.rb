module Textus
  module Read
    # Pure read: returns the on-disk envelope annotated with a freshness
    # verdict. Never triggers fetch; never invokes the orchestrator.
    #
    # For interactive reads that want fetch-on-stale, use
    # `Read::GetOrFetch`, which composes this with the orchestrator.
    class Get
      extend Textus::Contract::DSL

      verb     :get
      summary  "Read one entry. Returns the envelope (uid, etag, _meta, body, freshness)."
      surfaces :cli, :ruby, :mcp
      arg :key, String, required: true, positional: true,
                        description: "dotted entry key to read, e.g. 'knowledge.project'"
      response(&:to_h_for_wire)

      def initialize(container:, call:, evaluator: Textus::Domain::Freshness::Evaluator)
        @container  = container
        @call       = call
        @manifest   = container.manifest
        @file_store = container.file_store
        @evaluator  = evaluator
      end

      def call(key)
        envelope = read_raw_envelope(key)
        return nil if envelope.nil?

        policy_set = @manifest.rules.for(key)
        fetch_policy = policy_set.fetch
        return annotate_fresh(envelope) if fetch_policy.nil?

        policy = fetch_policy.to_freshness_policy
        verdict = @evaluator.call(policy, envelope, now: @call.now)

        envelope.with(freshness: Textus::Domain::Freshness.build(
          stale: verdict.stale?,
          reason: verdict.reason,
          fetching: false,
        ))
      end

      # Strict variant: raises UnknownKey when the entry is missing.
      # Used by consumers (e.g. Validator) that need to distinguish absence
      # from emptiness.
      def get(key)
        call(key) || raise(UnknownKey.new(key, suggestions: @manifest.resolver.suggestions_for(key)))
      end

      private

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
