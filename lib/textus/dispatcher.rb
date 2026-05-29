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
      get: Textus::Read::Get,
      get_or_refresh: Textus::Read::GetOrRefresh,
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
      policy_explain: Textus::Read::PolicyExplain,
      published: Textus::Read::Published,
      schema_envelope: Textus::Read::SchemaEnvelope,
      validate_all: Textus::Read::ValidateAll,
      doctor: Textus::Read::Doctor,

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
  end
end
