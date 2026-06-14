module Textus
  # Static verb → use-case map. Canonical lookup as of 0.27.0; replaces the
  # Application::UseCase registry whose entries were populated by file-load
  # side effects in 0.26.x.
  module Dispatcher
    VERBS = {
      # Write
      put: Textus::Dispatch::Actions::Put,
      propose: Textus::Dispatch::Actions::Propose,
      key_delete: Textus::Dispatch::Actions::KeyDelete,
      key_mv: Textus::Dispatch::Actions::KeyMv,
      accept: Textus::Dispatch::Actions::Accept,
      reject: Textus::Dispatch::Actions::Reject,
      enqueue: Textus::Dispatch::Actions::Enqueue,
      # Read
      get: Textus::Dispatch::Actions::Get,
      list: Textus::Dispatch::Actions::List,
      where: Textus::Dispatch::Actions::Where,
      uid: Textus::Dispatch::Actions::Uid,
      blame: Textus::Dispatch::Actions::Blame,
      audit: Textus::Dispatch::Actions::Audit,
      materialize: Textus::Dispatch::Actions::Materialize,
      refresh_data: Textus::Dispatch::Actions::RefreshData,
      sweep: Textus::Dispatch::Actions::Sweep,
      deps: Textus::Dispatch::Actions::Deps,
      rdeps: Textus::Dispatch::Actions::Rdeps,
      pulse: Textus::Dispatch::Actions::Pulse,
      rule_explain: Textus::Dispatch::Actions::RuleExplain,
      rule_list: Textus::Dispatch::Actions::RuleList,
      published: Textus::Dispatch::Actions::Published,
      schema_show: Textus::Dispatch::Actions::SchemaEnvelope,
      validate_all: Textus::Dispatch::Actions::ValidateAll,
      doctor: Textus::Dispatch::Actions::Doctor,
      boot: Textus::Dispatch::Actions::Boot,
      jobs: Textus::Dispatch::Actions::Jobs,

      # Maintenance
      data_mv: Textus::Dispatch::Actions::DataMv,
      key_mv_prefix: Textus::Dispatch::Actions::KeyMvPrefix,
      key_delete_prefix: Textus::Dispatch::Actions::KeyDeletePrefix,
      drain: Textus::Dispatch::Actions::Drain,
      rule_lint: Textus::Dispatch::Actions::RuleLint,
    }.freeze

    def self.fetch(verb)
      VERBS.fetch(verb.to_sym) { raise UsageError.new("unknown verb: #{verb.inspect}") }
    end

    # Single home for the uniform use-case invocation protocol (ADR 0023):
    # look up the verb, construct on (container:, call:), and invoke #call.
    def self.invoke(verb, container:, call:, args: [], kwargs: {})
      klass = fetch(verb)
      if klass <= Textus::Dispatch::Actions::Base
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
