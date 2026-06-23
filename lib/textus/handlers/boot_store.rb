module Textus
  module Handlers
    class BootStore
      def initialize(container:)
        @container = container
      end

      def call(_command, _call)
        Value::Result.success(Textus::Boot.build(container: @container))
      end
    end
  end
end
