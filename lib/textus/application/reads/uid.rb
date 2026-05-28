module Textus
  module Application
    module Reads
      class Uid
        def initialize(ctx:, caps:)
          @ctx = ctx
          @caps = caps
        end

        def call(key)
          get.get(key).uid
        end

        private

        def get
          @get ||= Get.new(ctx: @ctx, caps: @caps)
        end
      end
    end
  end
end
