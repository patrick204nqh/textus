module Textus
  module Application
    module Reads
      class List
        def initialize(ctx:)
          @ctx = ctx
        end

        def call(prefix: nil, zone: nil)
          @ctx.store.reader.list(prefix: prefix, zone: zone)
        end
      end
    end
  end
end
