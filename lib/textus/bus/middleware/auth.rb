module Textus
  module Bus
    module Middleware
      class Auth < Base
        middleware_name :auth

        def call(container:, command:, call:, next_handler:)
          verb = Bus.contract_to_verb!(command.class).to_sym
          key = key_for(command)

          rule_preds = key ? rule_declared_predicates(verb, container.manifest, key) : []

          Bus::Predicates.evaluate(
            manifest: container.manifest, schemas: container.schemas,
            action: verb, actor: call.role, key: key,
            rule_predicates: rule_preds,
          )

          next_handler.call(command, call)
        end

        private

        def rule_declared_predicates(verb, manifest, key)
          guard_map = manifest.rules.for(key).guard
          return [] if guard_map.nil?

          Array(guard_map[verb.to_s])
        end

        def key_for(command)
          if command.respond_to?(:key) then command.key
          elsif command.respond_to?(:old_key) then command.old_key
          elsif command.respond_to?(:pending_key) then command.pending_key
          else nil
          end
        end
      end
    end
  end
end
