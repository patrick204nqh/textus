module Textus
  module Value
    module Outcome
      Completed = Data.define(:details) do
        def kind = :completed
      end

      RetryableFailure = Data.define(:error) do
        def kind = :retryable_failure
      end

      DeadLettered = Data.define(:error) do
        def kind = :dead_lettered
      end

      SkippedLock = Data.define(:reason) do
        def kind = :skipped_lock
      end
    end
  end
end
