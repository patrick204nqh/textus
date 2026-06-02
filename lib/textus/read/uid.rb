module Textus
  module Read
    class Uid
      def initialize(container:, call:)
        @container = container
        @call      = call
      end

      def call(key)
        get.get(key).uid
      end

      private

      def get
        @get ||= GetEntry.new(container: @container, call: @call)
      end
    end
  end
end
