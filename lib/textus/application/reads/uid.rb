module Textus
  module Application
    module Reads
      class Uid
        def initialize(ctx:, ports:)
          @ctx   = ctx
          @ports = ports
        end

        def call(key)
          get.get(key).uid
        end

        private

        def get
          @get ||= Get.new(ctx: @ctx, ports: @ports)
        end
      end
    end
  end
end
