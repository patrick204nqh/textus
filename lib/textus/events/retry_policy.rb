module Textus
  module Events
    class RetryPolicy
      DEFAULT_BACKOFF_DELAYS = [10, 30, 60].freeze

      Decision = Data.define(:terminal, :delay) do
        def terminal? = terminal
      end

      def initialize(backoff_delays: DEFAULT_BACKOFF_DELAYS)
        @backoff_delays = backoff_delays
      end

      def decide(retry_count:, max_attempts:)
        return Decision.new(terminal: true, delay: nil) if retry_count >= max_attempts

        index = [retry_count - 1, @backoff_delays.length - 1].min
        Decision.new(terminal: false, delay: @backoff_delays[index])
      end
    end
  end
end
