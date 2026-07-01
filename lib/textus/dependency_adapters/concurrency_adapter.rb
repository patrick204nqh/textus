module Textus
  module DependencyAdapters
    class ConcurrencyAdapter
      def future(&)
        Concurrent::Promises.future(&)
      end

      def zip_futures(*promises)
        Concurrent::Promises.zip_futures(*promises)
      end
    end
  end
end
