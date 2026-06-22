module Textus
  module Handlers
    class UidEntry
      def initialize(compositor:)
        @compositor = compositor
      end

      def call(command, call)
        envelope = @compositor.read(command.key)
        return Result.failure(:not_found, "no entry at #{command.key}") unless envelope

        Result.success(envelope.uid)
      end
    end
  end
end
