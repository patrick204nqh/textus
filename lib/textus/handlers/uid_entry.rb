module Textus
  module Handlers
    class UidEntry
      def initialize(container:)
        @container = container
      end

      def call(command, _call)
        envelope = @container.pipeline.read(command.key)
        return Value::Result.failure(:not_found, "no entry at #{command.key}") unless envelope

        Value::Result.success(envelope.uid)
      end
    end
  end
end
