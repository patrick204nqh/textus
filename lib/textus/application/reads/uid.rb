module Textus
  module Application
    module Reads
      class Uid
        def initialize(ctx:, manifest:, file_store:)
          @ctx        = ctx
          @manifest   = manifest
          @file_store = file_store
        end

        def call(key)
          Get.new(ctx: @ctx, manifest: @manifest, file_store: @file_store).get(key).uid
        end
      end
    end
  end
end
