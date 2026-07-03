module Textus
  module Dispatch
    module Middleware
      class Auth < Base
        middleware_name :auth

        def call(container:, command:, call:, next_handler:)
          verb = Textus::Protocol::VerbRegistry.contract_to_verb!(command.class).to_sym
          key = key_for(command)

          Manifest::Policy::Predicates.evaluate(
            manifest: container.manifest, schemas: container.schemas,
            action: verb, actor: call.role, key: key,
            rule_predicates: []
          )

          next_handler.call(command, call)
        end

        private

        def key_for(command)
          if command.respond_to?(:key) then command.key
          elsif command.respond_to?(:old_key) then command.old_key
          elsif command.respond_to?(:pending_key) then command.pending_key
          end
        end
      end
    end
  end
end
