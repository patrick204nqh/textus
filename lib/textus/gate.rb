# frozen_string_literal: true

module Textus
  class Gate
    VERB_ACTIONS = {
      get: [Textus::Action::Get],
      put: [Textus::Action::Put],
      propose: [Textus::Action::Propose],
      key_delete: [Textus::Action::KeyDelete],
      key_mv: [Textus::Action::KeyMv],
      accept: [Textus::Action::Accept],
      reject: [Textus::Action::Reject],
      enqueue: [Textus::Action::Enqueue],
      list: [Textus::Action::List],
      where: [Textus::Action::Where],
      uid: [Textus::Action::Uid],
      blame: [Textus::Action::Blame],
      audit: [Textus::Action::Audit],
      deps: [Textus::Action::Deps],
      rdeps: [Textus::Action::Rdeps],
      pulse: [Textus::Action::Pulse],
      rule_explain: [Textus::Action::RuleExplain],
      rule_list: [Textus::Action::RuleList],
      rule_lint: [Textus::Action::RuleLint],
      published: [Textus::Action::Published],
      schema_show: [Textus::Action::SchemaEnvelope],
      doctor: [Textus::Action::Doctor],
      boot: [Textus::Action::Boot],
      jobs: [Textus::Action::Jobs],
      data_mv: [Textus::Action::DataMv],
      key_mv_prefix: [Textus::Action::KeyMvPrefix],
      key_delete_prefix: [Textus::Action::KeyDeletePrefix],
      drain: [Textus::Action::Drain],
      ingest: [Textus::Action::Ingest],
    }.freeze

    def initialize(container)
      @container = container
    end

    def dispatch(spec:, inputs:, role:, correlation_id: nil, session: nil)
      resolved = Binder.bind(spec, inputs, session: session)
      cmd = Value::Command.new(verb: spec.verb, params: resolved.freeze, role: role)

      cmd = normalize_propose_key(cmd) if cmd.verb == :propose
      action_classes = VERB_ACTIONS.fetch(cmd.verb) do
        raise Textus::UsageError.new("unknown command verb: #{cmd.verb}")
      end

      Gate::Auth.new(@container).check!(cmd)
      call_obj = build_call(cmd, correlation_id: correlation_id)
      results = action_classes.map { |klass| run_action(klass, resolved, call_obj) }
      results.length == 1 ? results.first : results
    end

    private

    def normalize_propose_key(cmd)
      return cmd if cmd.pending_key

      zone = @container.manifest.policy.propose_lane_for(cmd.role.to_s)
      key = zone ? "#{zone}.#{cmd.key}" : nil
      cmd.with(params: cmd.params.merge(pending_key: key))
    end

    def run_action(klass, params, call_obj)
      action = klass.new(**params)
      action.call(container: @container, call: call_obj)
    end

    def build_call(cmd, correlation_id: nil)
      dry_run = cmd.params.key?(:dry_run) ? !cmd.params[:dry_run].nil? : false
      Textus::Value::Call.build(role: cmd.role, dry_run:, correlation_id: correlation_id)
    end
  end
end
