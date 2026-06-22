module Textus
  module Handlers
    class GetEntry
      def initialize(compositor:, freshness_evaluator:)
        @compositor = compositor
        @freshness_evaluator = freshness_evaluator
      end

      def call(command, call)
        envelope = @compositor.read(command.key)
        return Result.failure(:not_found, "no entry at #{command.key}") unless envelope

        Result.success(envelope.with(freshness: @freshness_evaluator.verdict(resolve_entry(command.key))))
      end

      private

      def resolve_entry(key)
        @compositor.manifest.resolver.resolve(key).entry
      end
    end
  end
end
