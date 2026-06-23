module Textus
  module Handlers
    class GetEntry
      def initialize(container:, freshness_evaluator:)
        @container = container
        @freshness_evaluator = freshness_evaluator
      end

      def call(command, _call)
        envelope = @container.pipeline.read(command.key)
        return Result.failure(:not_found, "no entry at #{command.key}") unless envelope

        Result.success(envelope.with(freshness: @freshness_evaluator.verdict(resolve_entry(command.key))))
      end

      private

      def resolve_entry(key)
        @container.manifest.resolver.resolve(key).entry
      end
    end
  end
end
