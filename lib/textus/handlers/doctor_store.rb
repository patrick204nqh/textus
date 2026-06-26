module Textus
  module Handlers
    class DoctorStore
      def initialize(container:)
        @container = container
      end

      def call(command, call)
        Value::Result.success(Textus::Doctor.build(container: @container, checks: command.checks, role: call.role))
      end
    end
  end
end
