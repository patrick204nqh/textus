require "timeout"

module Textus
  module Produce
    module Acquire
      # Invokes a :resolve_handler hook handler by name under a timeout — the single
      # home for "call the intake handler under a deadline" (ADR 0048 D1). Shared by
      # Produce::Acquire::Intake (the internal ingest mechanism — no public verb since ADR 0079)
      # as driven by the converge sweep (drain/serve) and `textus hook run` (ADR 0089 made
      # ingest system-pushed; there is no read or put trigger).
      # Always passes a Container as `caps:` so the hook contract (ADR 0027) is
      # uniform across every entry point. Maps Timeout::Error to a UsageError;
      # leaves any other error to the caller (call sites differ in how they wrap).
      module Handler
        FETCH_TIMEOUT_SECONDS = 30

        module_function

        def invoke(caps:, handler:, config:, args:, label:, timeout: FETCH_TIMEOUT_SECONDS)
          Timeout.timeout(timeout) do
            caps.steps.invoke(:fetch, handler, caps: caps, config: config, args: args)
          end
        rescue Timeout::Error
          raise Textus::UsageError.new("#{label} '#{handler}' exceeded #{timeout}s timeout")
        end
      end
    end
  end
end
