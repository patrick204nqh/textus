module Textus
  class Store
    class TraceBuffer
      DEFAULT_SIZE = 100

      def initialize(max_size: DEFAULT_SIZE)
        @max_size = max_size
        @buffer = []
        @mutex = Mutex.new
      end

      def append(trace)
        @mutex.synchronize do
          @buffer << trace
          @buffer.shift if @buffer.size > @max_size
        end
      end

      def recent(limit: 20)
        @mutex.synchronize do
          @buffer.last(limit)
        end
      end

      def clear!
        @mutex.synchronize { @buffer.clear }
      end

      def stats
        @mutex.synchronize do
          total = @buffer.size
          errors = @buffer.count { |t| !t.success? }
          avg_ms = total.zero? ? 0.0 : @buffer.sum(&:duration_ms).to_f / total
          { total:, errors:, avg_duration_ms: avg_ms.round(1) }
        end
      end
    end
  end
end
