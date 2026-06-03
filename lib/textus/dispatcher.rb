module Textus
  # Static verb → use-case map. Canonical lookup as of 0.27.0; replaces the
  # Application::UseCase registry whose entries were populated by file-load
  # side effects in 0.26.x.
  module Dispatcher
    VERBS = {
      # Write
      put: Textus::Write::Put,
      propose: Textus::Write::Propose,
      delete: Textus::Write::Delete,
      mv: Textus::Write::Mv,
      accept: Textus::Write::Accept,
      reject: Textus::Write::Reject,
      build: Textus::Write::Build,
      fetch: Textus::Write::FetchWorker,
      fetch_all: Textus::Write::FetchAll,
      retain: Textus::Write::RetentionSweep,

      # Read
      get: Textus::Read::Get,
      list: Textus::Read::List,
      where: Textus::Read::Where,
      uid: Textus::Read::Uid,
      blame: Textus::Read::Blame,
      audit: Textus::Read::Audit,
      freshness: Textus::Read::Freshness,
      stale: Textus::Read::Stale,
      deps: Textus::Read::Deps,
      rdeps: Textus::Read::Rdeps,
      pulse: Textus::Read::Pulse,
      rule_explain: Textus::Read::RuleExplain,
      rule_list: Textus::Read::RuleList,
      published: Textus::Read::Published,
      schema_show: Textus::Read::SchemaEnvelope,
      validate_all: Textus::Read::ValidateAll,
      doctor: Textus::Read::Doctor,
      boot: Textus::Read::Boot,
      retainable: Textus::Read::Retainable,
      capabilities: Textus::Read::Capabilities,

      # Maintenance
      migrate: Textus::Maintenance::Migrate,
      zone_mv: Textus::Maintenance::ZoneMv,
      key_mv_prefix: Textus::Maintenance::KeyMvPrefix,
      key_delete_prefix: Textus::Maintenance::KeyDeletePrefix,
      rule_lint: Textus::Maintenance::RuleLint,
    }.freeze

    def self.fetch(verb)
      VERBS.fetch(verb.to_sym) { raise UsageError.new("unknown verb: #{verb.inspect}") }
    end

    # Single home for the uniform use-case invocation protocol (ADR 0023):
    # look up the verb, construct on (container:, call:), and invoke #call.
    def self.invoke(verb, container:, call:, args: [], kwargs: {})
      fetch(verb).new(container: container, call: call).call(*args, **kwargs)
    end
  end
end
