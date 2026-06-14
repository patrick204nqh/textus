# frozen_string_literal: true

module Textus
  class Gate
    class Auth
      def initialize(container)
        @inner = Textus::Dispatch::Auth.new(
          manifest: container.manifest,
          schemas: container.schemas,
        )
      end

      def check!(cmd)
        return if cmd.role.to_s == Textus::Role::AUTOMATION

        key = cmd.respond_to?(:key) ? cmd.key : nil
        return unless key

        action_sym = command_to_action(cmd)
        @inner.check!(action: action_sym, actor: cmd.role, key: key)
      end

      private

      def command_to_action(cmd)
        cmd.class.name.split("::").last
           .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .downcase
           .to_sym
      end
    end
  end
end
