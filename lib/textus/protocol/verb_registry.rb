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

      require_relative "verb_registry/core_verbs"
      CoreVerbs.each_value { |spec| register(spec) }

      require_relative "../lanes/knowledge/verbs"
      require_relative "../lanes/scratchpad/verbs"
      require_relative "../lanes/artifact/verbs"
    end
  end
end
