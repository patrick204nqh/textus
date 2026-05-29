module Textus
  # Static verb → use-case map. Canonical lookup as of 0.27.0; replaces the
  # Application::UseCase registry whose entries were populated by file-load
  # side effects in 0.26.x.
  module Dispatcher
    VERBS = {
      # Write
      put: Textus::Write::Put,
      delete: Textus::Write::Delete,
      mv: Textus::Write::Mv,
      accept: Textus::Write::Accept,
      reject: Textus::Write::Reject,
      publish: Textus::Write::Publish,
      refresh: Textus::Write::RefreshWorker,
      refresh_all: Textus::Write::RefreshAll,

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
