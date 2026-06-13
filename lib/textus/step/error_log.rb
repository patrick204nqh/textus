module Textus
  module Step
    # Bounded in-memory ring buffer of recent hook failures (errored and
    # timed_out). Each row carries the audit `seq` observed at the time of
    # failure so pulse can filter "errors since cursor".
    class ErrorLog
      DEFAULT_CAPACITY = 256

      def initialize(capacity: DEFAULT_CAPACITY)
        @capacity = capacity
        @rows = []
        @mutex = Mutex.new
      end

      def record(seq:, event:, hook:, key:, error_class:, error_message:)
        row = {
          seq: seq, event: event, hook: hook, key: key,
          error_class: error_class, error_message: error_message,
          at: Time.now.utc.iso8601
        }
        @mutex.synchronize do
          @rows << row
          @rows.shift while @rows.size > @capacity
        end
      end

      def since(seq)
        @mutex.synchronize { @rows.select { |r| r[:seq] > seq }.dup }
      end
    end
  end
end
