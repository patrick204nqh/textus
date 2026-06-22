module Textus
  module Value
    Result = Data.define(:ok, :value, :error) do
      def self.success(value) = new(ok: true, value: value, error: nil)

      def self.failure(code, message, details: {})
        new(ok: false, value: nil, error: { code: code, message: message, details: details })
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
  end
end
