module Textus
  module Application
    module Reads
      class Uid
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(key)
          Get.new(ctx: @ctx).get(key).uid
        end
      end
    end
  end
end
