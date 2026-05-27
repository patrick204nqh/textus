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
          get.get(key).uid
        end

        private

        def get
          @get ||= Get.new(ctx: @ctx, manifest: @manifest, file_store: @file_store)
        end
      end
    end
  end
end
