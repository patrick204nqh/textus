# frozen_string_literal: true

module Textus
  class Gate
    VERB_COMMAND = {
      get: Textus::Command::Get,
      put: Textus::Command::Put,
      propose: Textus::Command::Propose,
      key_delete: Textus::Command::KeyDelete,
      key_mv: Textus::Command::KeyMv,
      accept: Textus::Command::Accept,
      reject: Textus::Command::Reject,
      enqueue: Textus::Command::Enqueue,
      list: Textus::Command::List,
      where: Textus::Command::Where,
      uid: Textus::Command::Uid,
      blame: Textus::Command::Blame,
      audit: Textus::Command::Audit,
      deps: Textus::Command::Deps,
      rdeps: Textus::Command::Rdeps,
      pulse: Textus::Command::Pulse,
      rule_explain: Textus::Command::RuleExplain,
      rule_list: Textus::Command::RuleList,
      rule_lint: Textus::Command::RuleLint,
      published: Textus::Command::Published,
      schema_show: Textus::Command::SchemaShow,
      doctor: Textus::Command::Doctor,
      boot: Textus::Command::Boot,
      jobs: Textus::Command::Jobs,
      data_mv: Textus::Command::DataMv,
      key_mv_prefix: Textus::Command::KeyMvPrefix,
      key_delete_prefix: Textus::Command::KeyDeletePrefix,
      drain: Textus::Command::Drain,
    }.freeze

    ROUTES = {
      Command::Get => [Textus::Action::Get],
      Command::Put => [Textus::Action::Put],
      Command::Propose => [Textus::Action::Propose],
      Command::KeyDelete => [Textus::Action::KeyDelete],
      Command::KeyMv => [Textus::Action::KeyMv],
      Command::Accept => [Textus::Action::Accept],
      Command::Reject => [Textus::Action::Reject],
      Command::Enqueue => [Textus::Action::Enqueue],
      Command::List => [Textus::Action::List],
      Command::Where => [Textus::Action::Where],
      Command::Uid => [Textus::Action::Uid],
      Command::Blame => [Textus::Action::Blame],
      Command::Audit => [Textus::Action::Audit],
      Command::Deps => [Textus::Action::Deps],
      Command::Rdeps => [Textus::Action::Rdeps],
      Command::Pulse => [Textus::Action::Pulse],
      Command::RuleExplain => [Textus::Action::RuleExplain],
      Command::RuleList => [Textus::Action::RuleList],
      Command::RuleLint => [Textus::Action::RuleLint],
      Command::Published => [Textus::Action::Published],
      Command::SchemaShow => [Textus::Action::SchemaEnvelope],
      Command::Doctor => [Textus::Action::Doctor],
      Command::Boot => [Textus::Action::Boot],
      Command::Jobs => [Textus::Action::Jobs],
      Command::DataMv => [Textus::Action::DataMv],
      Command::KeyMvPrefix => [Textus::Action::KeyMvPrefix],
      Command::KeyDeletePrefix => [Textus::Action::KeyDeletePrefix],
      Command::Drain => [Textus::Action::Drain],
    }.freeze

    def initialize(container)
      @container = container
    end

    def dispatch(cmd, container: @container)
      action_classes = ROUTES.fetch(cmd.class) do
        raise Textus::UsageError.new("unknown command: #{cmd.class}")
      end

      Gate::Auth.new(container).check!(cmd)
      call_obj = build_call(cmd)
      results = action_classes.map { |klass| run_action(klass, cmd, container, call_obj) }
      results.one? ? results.first : results
    end

    private

    def run_action(klass, cmd, container, call_obj)
      action = klass.new(**extract_kwargs(klass, cmd))
      action.call(container:, call: call_obj)
    end

    def extract_kwargs(klass, cmd)
      params = klass.instance_method(:initialize).parameters
      accepts_role = params.any? { |t, n| n == :role && %i[keyreq key].include?(t) } || params.any? { |t, _| t == :keyrest }
      cmd.members.each_with_object({}) do |m, h|
        next if m == :role && !accepts_role

        val = cmd.public_send(m)
        h[m] = val unless val.nil?
      end
    end

    def build_call(cmd)
      dry_run = cmd.respond_to?(:dry_run) ? !cmd.dry_run.nil? : false
      Textus::Call.build(role: cmd.role, dry_run:)
    end
  end
end
