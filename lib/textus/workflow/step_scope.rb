module Textus
  module Workflow
    class StepScope
      include Helpers

      def initialize(data, ctx, _runner)
        @data = data
        @ctx  = ctx
        @container = ctx.container
        @call = ctx.call
      end

      def call(callable)
        instance_exec(@data, @ctx, &callable)
      end
    end
  end
end
