require "timeout"

module Textus
  module Write
    # Invokes a :resolve_intake hook handler by name under a timeout — the single
    # home for "call the intake handler under a deadline" (ADR 0048 D1). Shared by
    # FetchWorker (the :fetch verb), `textus put --fetch`, and `textus hook run`.
    # Always passes a Container as `caps:` so the hook contract (ADR 0027) is
    # uniform across every entry point. Maps Timeout::Error to a UsageError;
    # leaves any other error to the caller (call sites differ in how they wrap).
    module IntakeFetch
      FETCH_TIMEOUT_SECONDS = 30

      module_function

      def invoke(caps:, handler:, config:, args:, label:, timeout: FETCH_TIMEOUT_SECONDS)
        Timeout.timeout(timeout) do
          caps.rpc.invoke(:resolve_intake, handler, caps: caps, config: config, args: args)
        end
      rescue Timeout::Error
        raise Textus::UsageError.new("#{label} '#{handler}' exceeded #{timeout}s timeout")
      end
    end
  end
end
