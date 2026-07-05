module Textus
  module Protocol
    module VerbRegistry
      require_relative "verb_registry/arg_spec"
      require_relative "verb_registry/verb_spec"

      VERBS = {}
      POSITIONAL = {}

      def self.register(spec)
        VERBS[spec.verb] = spec
        POSITIONAL[spec.verb] = spec.args.select(&:positional).map(&:name)
      end

      def self.for(verb) = VERBS[verb]
      def self.positional_for(verb) = POSITIONAL[verb] || []
      def self.summary_for(verb) = VERBS[verb]&.summary
      def self.registered = VERBS.values

      ENTRY_VERBS = %i[
        get put list key_delete key_mv propose accept reject
        audit blame where uid deps rdeps graph diff ingest loop
        session_open session_close
      ].freeze

      OPS_VERBS = %i[
        boot drain pulse data_mv
        key_mv_prefix key_delete_prefix
      ].freeze

      VERB_DOMAIN = ENTRY_VERBS.to_h { |v| [v, :entry] }
                               .merge(OPS_VERBS.to_h { |v| [v, :ops] }).freeze

      require_relative "verb_registry/verbs/get"
      require_relative "verb_registry/verbs/put"
      require_relative "verb_registry/verbs/list"
      require_relative "verb_registry/verbs/key_delete"
      require_relative "verb_registry/verbs/key_mv"
      require_relative "verb_registry/verbs/ingest"
      require_relative "verb_registry/verbs/where"
      require_relative "verb_registry/verbs/uid"
      require_relative "verb_registry/verbs/blame"
      require_relative "verb_registry/verbs/audit"
      require_relative "verb_registry/verbs/deps"
      require_relative "verb_registry/verbs/rdeps"
      require_relative "verb_registry/verbs/graph"
      require_relative "verb_registry/verbs/pulse"
      require_relative "verb_registry/verbs/schema_show"
      require_relative "verb_registry/verbs/schema_list"
      require_relative "verb_registry/verbs/boot"
      require_relative "verb_registry/verbs/data_mv"
      require_relative "verb_registry/verbs/key_mv_prefix"
      require_relative "verb_registry/verbs/key_delete_prefix"
      require_relative "verb_registry/verbs/drain"

      require_relative "../lanes/knowledge/verbs"
      require_relative "../lanes/scratchpad/verbs"
      require_relative "../lanes/artifact/verbs"
    end
  end
end
