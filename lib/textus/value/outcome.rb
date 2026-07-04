module Textus
  module Value
    module Outcome
      Completed = Data.define(:details) do
        def kind = :completed
      end

      DeadLettered = Data.define(:error) do
        def kind = :dead_lettered
      end
    end
  end
end
