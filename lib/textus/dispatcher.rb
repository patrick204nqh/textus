module Textus
  # Static verb → use-case map. Replaces the Application::UseCase registry
  # whose entries were populated by file-load side effects.
  #
  # During Phase 3 of the 0.27.0 redesign this table coexists with
  # Application::UseCase. The registry is removed in Phase 7; Dispatcher
  # becomes the canonical lookup.
  module Dispatcher
    VERBS = {
      # Write
      put: Textus::Application::Write::Put,
      delete: Textus::Application::Write::Delete,
      mv: Textus::Application::Write::Mv,
      accept: Textus::Application::Write::Accept,
      reject: Textus::Application::Write::Reject,
      publish: Textus::Application::Write::Publish,
      refresh: Textus::Application::Write::RefreshWorker,
      refresh_all: Textus::Application::Write::RefreshAll,

      # Read
      get: Textus::Application::Read::Get,
      get_or_refresh: Textus::Application::Read::GetOrRefresh,
      list: Textus::Application::Read::List,
      where: Textus::Application::Read::Where,
      uid: Textus::Application::Read::Uid,
      blame: Textus::Application::Read::Blame,
      audit: Textus::Application::Read::Audit,
      freshness: Textus::Application::Read::Freshness,
      stale: Textus::Application::Read::Stale,
      deps: Textus::Application::Read::Deps,
      rdeps: Textus::Application::Read::Rdeps,
      pulse: Textus::Application::Read::Pulse,
      policy_explain: Textus::Application::Read::PolicyExplain,
      published: Textus::Application::Read::Published,
      schema_envelope: Textus::Application::Read::SchemaEnvelope,
      validate_all: Textus::Application::Read::ValidateAll,

      # Maintenance
      migrate: Textus::Application::Maintenance::Migrate,
      zone_mv: Textus::Application::Maintenance::ZoneMv,
      key_mv_prefix: Textus::Application::Maintenance::KeyMvPrefix,
      key_delete_prefix: Textus::Application::Maintenance::KeyDeletePrefix,
      rule_lint: Textus::Application::Maintenance::RuleLint,
    }.freeze

    def self.fetch(verb)
      VERBS.fetch(verb.to_sym) { raise UsageError.new("unknown verb: #{verb.inspect}") }
    end
  end
end
