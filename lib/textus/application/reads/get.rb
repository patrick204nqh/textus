module Textus
  module Application
    module Reads
      class Get
        def initialize(ctx:, orchestrator:, evaluator: Textus::Domain::Freshness::Evaluator)
          @ctx          = ctx
          @orchestrator = orchestrator
          @evaluator    = evaluator
        end

        def call(key)
          envelope = @ctx.store.reader.read_raw_envelope(key)
          return nil if envelope.nil?

          mentry = @ctx.store.manifest.resolve(key).first
          policy = mentry.policy
          verdict = @evaluator.call(policy, envelope, now: @ctx.now)

          return annotate(envelope, verdict, refreshing: false) if verdict.fresh?

          action = policy.decide(verdict)
          outcome = @orchestrator.execute(action, key: key, as: @ctx.role)

          case outcome
          when Textus::Domain::Outcome::Skipped
            annotate(envelope, verdict, refreshing: false)
          when Textus::Domain::Outcome::Refreshed
            fresh_verdict = @evaluator.call(policy, outcome.envelope, now: @ctx.now)
            annotate(outcome.envelope, fresh_verdict, refreshing: false)
          when Textus::Domain::Outcome::Detached
            annotate(envelope, verdict, refreshing: true)
          when Textus::Domain::Outcome::Failed
            annotate(envelope, verdict, refreshing: false, refresh_error: outcome.error.message)
          end
        end

        private

        def annotate(envelope, verdict, refreshing:, refresh_error: nil)
          envelope = envelope.dup
          envelope["stale"]         = verdict.stale?
          envelope["stale_reason"]  = verdict.reason
          envelope["refreshing"]    = refreshing
          envelope["refresh_error"] = refresh_error if refresh_error
          envelope
        end
      end
    end
  end
end
