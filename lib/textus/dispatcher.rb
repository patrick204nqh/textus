module Textus
  module Dispatcher
    VERBS = {
      put: Textus::Action::Put,
      propose: Textus::Action::Propose,
      key_delete: Textus::Action::KeyDelete,
      key_mv: Textus::Action::KeyMv,
      accept: Textus::Action::Accept,
      reject: Textus::Action::Reject,
      enqueue: Textus::Action::Enqueue,
      get: Textus::Action::Get,
      list: Textus::Action::List,
      where: Textus::Action::Where,
      uid: Textus::Action::Uid,
      blame: Textus::Action::Blame,
      audit: Textus::Action::Audit,
      materialize: Textus::Action::Background::Materialize,
      refresh: Textus::Action::Background::Refresh,
      sweep: Textus::Action::Background::Sweep,
      deps: Textus::Action::Deps,
      rdeps: Textus::Action::Rdeps,
      pulse: Textus::Action::Pulse,
      rule_explain: Textus::Action::RuleExplain,
      rule_list: Textus::Action::RuleList,
      published: Textus::Action::Published,
      schema_show: Textus::Action::SchemaEnvelope,
      doctor: Textus::Action::Doctor,
      boot: Textus::Action::Boot,
      jobs: Textus::Action::Jobs,
      data_mv: Textus::Action::DataMv,
      key_mv_prefix: Textus::Action::KeyMvPrefix,
      key_delete_prefix: Textus::Action::KeyDeletePrefix,
      drain: Textus::Action::Drain,
      rule_lint: Textus::Action::RuleLint,
    }.freeze

    def self.fetch(verb)
      VERBS.fetch(verb.to_sym) { raise UsageError.new("unknown verb: #{verb.inspect}") }
    end

    def self.invoke(verb, container:, call:, args: [], kwargs: {})
      klass = fetch(verb)
      if klass <= Textus::Action::Base
        init_kwargs = kwargs.dup
        if klass.respond_to?(:contract?) && klass.contract? && !args.empty?
          klass.contract.args.select(&:positional).zip(args).each do |arg_spec, value|
            init_kwargs[arg_spec.name] = value unless init_kwargs.key?(arg_spec.name)
          end
        end
        klass.new(**init_kwargs).call(container: container, call: call)
      else
        klass.new(container: container, call: call).call(*args, **kwargs)
      end
    end
  end
end
