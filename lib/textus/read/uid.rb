module Textus
  module Read
    class Uid
      def initialize(container:, call:, hook_context: nil) # rubocop:disable Lint/UnusedMethodArgument
        @container = container
        @call      = call
      end

      def call(key)
        get.get(key).uid
      end

      private

      def get
        @get ||= Get.new(container: @container, call: @call)
      end
    end
  end
end
