# frozen_string_literal: true

module Textus
  class Gate
    VERB_ACTIONS = {
      get:              [Textus::Action::Get],
      put:              [Textus::Action::Put],
      propose:          [Textus::Action::Propose],
      key_delete:       [Textus::Action::KeyDelete],
      key_mv:           [Textus::Action::KeyMv],
      accept:           [Textus::Action::Accept],
      reject:           [Textus::Action::Reject],
      enqueue:          [Textus::Action::Enqueue],
      list:             [Textus::Action::List],
      where:            [Textus::Action::Where],
      uid:              [Textus::Action::Uid],
      blame:            [Textus::Action::Blame],
      audit:            [Textus::Action::Audit],
      deps:             [Textus::Action::Deps],
      rdeps:            [Textus::Action::Rdeps],
      pulse:            [Textus::Action::Pulse],
      rule_explain:     [Textus::Action::RuleExplain],
      rule_list:        [Textus::Action::RuleList],
      rule_lint:        [Textus::Action::RuleLint],
      published:        [Textus::Action::Published],
      schema_show:      [Textus::Action::SchemaEnvelope],
      doctor:           [Textus::Action::Doctor],
      boot:             [Textus::Action::Boot],
      jobs:             [Textus::Action::Jobs],
      data_mv:          [Textus::Action::DataMv],
      key_mv_prefix:    [Textus::Action::KeyMvPrefix],
      key_delete_prefix:[Textus::Action::KeyDeletePrefix],
      drain:            [Textus::Action::Drain],
      ingest:           [Textus::Action::Ingest],
    }.freeze

    def initialize(container)
      @container = container
    end

    def dispatch(cmd, correlation_id: nil)
      cmd = normalize_propose_key(cmd, @container) if cmd.verb == :propose
      action_classes = VERB_ACTIONS.fetch(cmd.verb) do
        raise Textus::UsageError.new("unknown command verb: #{cmd.verb}")
      end

      Gate::Auth.new(@container).check!(cmd)
      call_obj = build_call(cmd, correlation_id: correlation_id)
      results = action_classes.map { |klass| run_action(klass, cmd, @container, call_obj) }
      results.length == 1 ? results.first : results
    end

    private

    def normalize_propose_key(cmd, container)
      return cmd if cmd.pending_key

      zone = container.manifest.policy.propose_lane_for(cmd.role.to_s)
      key = zone ? "#{zone}.#{cmd.key}" : nil
      cmd.with(params: cmd.params.merge(pending_key: key))
    end

    def run_action(klass, cmd, container, call_obj)
      action = klass.new(**extract_kwargs(klass, cmd))
      action.call(container:, call: call_obj)
    end

    def extract_kwargs(klass, cmd)
      params = klass.instance_method(:initialize).parameters
      accepts_keyrest = params.any? { |t, _| t == :keyrest }
      param_set = params.to_set { |_t, n| n }
      cmd.params.each_with_object({}) do |(m, val), h|
        next unless accepts_keyrest || param_set.include?(m)
        h[m] = val unless val.nil?
      end
    end

    def build_call(cmd, correlation_id: nil)
      dry_run = cmd.params.key?(:dry_run) ? !cmd.params[:dry_run].nil? : false
      Textus::Call.build(role: cmd.role, dry_run:, correlation_id: correlation_id)
    end
  end
end
