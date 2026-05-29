require "timeout"

module Textus
  module Write
    # Invokes a :resolve_intake hook handler by name under a timeout.
    # The transport-side fetch kernel shared by `textus put --fetch` and
    # `textus hook run`. Maps Timeout::Error to a UsageError; leaves any
    # other error to the caller (call sites differ in how they wrap those).
    module IntakeFetch
      FETCH_TIMEOUT_SECONDS = 30

      module_function

      def invoke(rpc:, handler:, config:, args:, label:, timeout: FETCH_TIMEOUT_SECONDS)
        Timeout.timeout(timeout) do
          rpc.invoke(:resolve_intake, handler, caps: nil, config: config, args: args)
        end
      rescue Timeout::Error
        raise Textus::UsageError.new("#{label} '#{handler}' exceeded #{timeout}s timeout")
      end
    end
  end
end
