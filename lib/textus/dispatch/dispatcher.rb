module Textus
  module Dispatch
    module Dispatcher
      module_function

      def dispatch(spec, inputs, store:, role:, session: nil, scope: nil, correlation_id: nil) # rubocop:disable Metrics/ParameterLists
        resolved = Binder.bind(spec, inputs, session: session)
        cmd = Textus::Value::Command.new(verb: spec.verb, params: resolved.freeze, role: role)

        if spec.verb == :pulse && !session && scope
          cursor_store = Textus::Store::Cursor.new(root: scope.container.root, role: scope.role)
          cmd = cmd.with(params: cmd.params.merge(since: cursor_store.read)) unless cmd.params.key?(:since)
          result = store.gate.dispatch(cmd, correlation_id: correlation_id)
          cursor_store.write(result["cursor"]) if result.is_a?(Hash) && result["cursor"]
          result
        else
          store.gate.dispatch(cmd, correlation_id: correlation_id)
        end
      end
    end
  end
end
