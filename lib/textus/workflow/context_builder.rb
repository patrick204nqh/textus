module Textus
  module Workflow
    class ContextBuilder
      def initialize(container, call)
        @container = container
        @call = call
      end

      def build(key)
        res = @container.manifest.resolver.resolve(key)
        Runner::Context.new(
          key: key,
          entry: res.entry,
          config: {}.freeze,
          lane: res.entry.lane.to_s,
          container: @container,
          call: @call,
        )
      end
    end
  end
end
