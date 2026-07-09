module Textus
  module Protocol
    module ActionRegistry
      require_relative "action_registry/arg_spec"
      require_relative "action_registry/action_spec"

      ACTIONS = {}
      POSITIONAL = {}

      def self.register(spec)
        ACTIONS[spec.action] = spec
        POSITIONAL[spec.action] = spec.args.select(&:positional).map(&:name)
      end

      def self.for(action) = ACTIONS[action]
      def self.positional_for(action) = POSITIONAL[action] || []
      def self.summary_for(action) = ACTIONS[action]&.summary
      def self.registered = ACTIONS.values

      ENTRY_ACTIONS = %i[
        get put list key_delete key_mv propose accept reject
        audit blame blueprint where uid deps rdeps graph diff ingest loop
        session_open session_close
      ].freeze

      NODE_ACTIONS = %i[
        node_enter node_exit node_back node_switch node_status
      ].freeze

      OPS_ACTIONS = %i[
        boot drain pulse data_mv
        key_mv_under key_delete_under
      ].freeze

      ACTION_DOMAIN = ENTRY_ACTIONS.to_h { |v| [v, :entry] }
                               .merge(OPS_ACTIONS.to_h { |v| [v, :ops] }).freeze

      require_relative "action_registry/core_actions"
      CoreActions.each_value { |spec| register(spec) }

      require_relative "../lanes/knowledge/actions"
      require_relative "../lanes/scratchpad/actions"
      require_relative "../lanes/artifact/actions"
      require_relative "action_registry/node_actions"
    end
  end
end
