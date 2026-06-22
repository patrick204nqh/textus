module Textus
  module Value
    module Result
      def self.unwrap(result)
        case result
        when Dry::Monads::Result::Success then result.value!
        when Dry::Monads::Result::Failure
          failure = result.failure
          raise ActionError.new(
            failure[:code] || :internal,
            failure[:message] || "action failed",
            details: failure[:details] || {},
          )
        else
          result
        end
      end
    end
  end
end
