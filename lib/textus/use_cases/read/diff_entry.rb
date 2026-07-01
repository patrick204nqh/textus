module Textus
  module UseCases
    module Read
      module DiffEntry
        HANDLES = Dispatch::Contracts::DiffEntry
        NEEDS = %i[file_store manifest layout].freeze

        def self.call(command, _call, deps)
          reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
          proposal_env = reader.read(command.pending_key)
          target_key = proposal_target_key(proposal_env, command.pending_key)
          return target_key if target_key.is_a?(Value::Result)

          target_env = reader.read(target_key)

          body_diff = Textus::Diff.body(target_env&.body, proposal_env.body)
          meta_diff = Textus::Diff.meta(target_env&.meta&.dig("_meta") || {}, proposal_env.meta&.dig("_meta") || {})

          target_schema = target_schema_ref(target_key, deps)
          proposal_schema = proposal_env&.meta&.dig("_meta", "schema")
          schema_diff = diff_schema(target_schema, proposal_schema)

          result = { "pending_key" => command.pending_key, "target_key" => target_key }
          result["body"] = body_diff if body_diff
          result["meta"] = meta_diff if meta_diff
          result["schema"] = schema_diff if schema_diff
          result["summary"] = Textus::Diff.summary(result)

          Value::Result.success(result)
        end

        def self.proposal_target_key(proposal_env, pending_key)
          proposal = proposal_env&.meta&.dig("proposal")
          return Value::Result.failure(:proposal_error, "entry has no proposal block: #{pending_key}") unless proposal

          target_key = proposal["target_key"]
          return Value::Result.failure(:proposal_error, "proposal missing target_key") unless target_key

          target_key
        end

        def self.diff_schema(target_schema, proposal_schema)
          return nil unless proposal_schema && target_schema != proposal_schema

          Textus::Diff.schema({ "schema" => target_schema }, { "schema" => proposal_schema })
        end

        def self.target_schema_ref(key, deps)
          entry = deps.manifest.data.entries.find { |e| e.key == key }
          entry&.schema_ref
        end
      end
    end
  end
end
