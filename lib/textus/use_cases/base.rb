module Textus
  module UseCases
    class Base
      class << self
        def handles(contract)
          @handles_contract = contract
        end

        def needs(*fields)
          @needs_fields = fields
          attr_reader(*fields)
        end

        attr_reader :handles_contract, :needs_fields

        def call(command, call, deps)
          instance = new
          instance.send(:setup, command, call, deps)
          instance.call
        end
      end

      def success(value) = Textus::Value::Result.success(value)
      def failure(code, message, details: {}) = Textus::Value::Result.failure(code, message, details:)

      private

      attr_reader :command, :call

      def setup(command, call, deps)
        @command = command
        @call = call
        self.class.needs_fields.each do |field|
          instance_variable_set(:"@#{field}", deps.public_send(field))
        end
      end
    end
  end
end
