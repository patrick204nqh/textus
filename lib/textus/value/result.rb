module Textus
  module Value
    # rubocop:disable Lint/ConstantDefinitionInBlock
    Result = Data.define(:ok, :value, :error) do
      def self.success(value) = new(ok: true, value: value, error: nil)

      def self.failure(code, message, details: {})
        new(ok: false, value: nil, error: { code: code, message: message, details: details })
      end

      def self.extract(result)
        case result
        when self
          if result.success?
            result.value
          else
            err = result.error
            raise Textus::ActionError.new(err[:code] || :error, err[:message] || "action failed", details: err[:details] || {})
          end
        else
          result
        end
      end

      def success? = ok
      def failure? = !ok

      def unwrap
        raise Result::UnwrapError.new(error[:code], error[:message], details: error[:details]) unless ok

        value
      end

      class UnwrapError < StandardError
        attr_reader :code, :details

        def initialize(code, message, details: {})
          super(message)
          @code = code
          @details = details
        end
      end
    end
    # rubocop:enable Lint/ConstantDefinitionInBlock
  end
end
