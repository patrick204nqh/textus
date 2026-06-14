require "zeitwerk"
require_relative "textus/version"
require_relative "textus/errors"
require_relative "textus/surfaces/mcp"
require_relative "textus/surfaces/mcp/errors"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "cli" => "CLI",
  "json" => "Json",
  "yaml" => "Yaml",
  "io" => "IO",
  "mcp" => "MCP",
  "mcp_serve" => "MCPServe",
)
loader.ignore(File.expand_path("textus/errors.rb", __dir__))
loader.ignore(File.expand_path("textus/surfaces/mcp.rb", __dir__))
loader.ignore(File.expand_path("textus/surfaces/mcp/errors.rb", __dir__))
# Scaffold sources copied verbatim into user stores by `textus init`. They are
# templates for user-owned step classes, not gem constants — Zeitwerk must not
# manage or eager-load them.
loader.ignore(File.expand_path("textus/init/templates", __dir__))
loader.setup
loader.eager_load

# Verb symbol → Action class mapping. Replaces Textus::Dispatcher::VERBS.
Textus::Action::VERBS = {
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
  # materialize, refresh, sweep are Worker-only — not in VERBS
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

# Derive CLI_VERBS after VERBS is available.
Textus::Boot::CLI_VERBS = Textus::Boot.build_cli_verbs.freeze

# Dynamic verb methods on Store (deferred after VERBS is defined).
Textus::Action::VERBS.each_key do |verb|
  Textus::Store.define_method(verb) do |*args, role: Textus::Role::DEFAULT, **kwargs|
    as(role).public_send(verb, *args, **kwargs)
  end

  Textus::Surfaces::RoleScope.define_method(verb) do |*args, **kwargs|
    klass = Textus::Action::VERBS[verb]
    inputs =
      if klass.respond_to?(:contract?) && klass.contract?
        Textus::Contract::Binder.inputs_from_ordered(klass.contract, args, kwargs)
      else
        kwargs
      end
    dispatch_bound(verb, inputs).first
  end
end

module Textus
end
