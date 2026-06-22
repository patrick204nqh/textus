# frozen_string_literal: true

module Textus
  module Value
    # Unwraps Dry::Monads results at the Gate seam.
    # Every action returns Success(value) or Failure(code:, message:, details:).
    # This module converts Failure into an ActionError for surfaces (CLI, MCP)
    # that expect exceptions.
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
