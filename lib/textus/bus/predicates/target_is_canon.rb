module Textus
  module Bus
    module Predicates
      class TargetIsCanon
        def initialize(manifest)
          @manifest = manifest
        end

        def call(command, call)
          key = command.respond_to?(:target_key) ? command.target_key : command.respond_to?(:key) ? command.key : nil
          return unless key

          mentry = resolve_entry(key)
          kind = @manifest.policy.declared_kind(mentry.lane.to_s)
          return if kind == :canon

          raise Textus::ProposalError.new("target lane '#{mentry.lane}' is not canon (kind: #{kind})")
        end

        private

        def resolve_entry(key)
          @manifest.resolver.resolve(key).entry
        rescue Textus::UnknownKey
          nil
        end
      end
    end
  end
end
