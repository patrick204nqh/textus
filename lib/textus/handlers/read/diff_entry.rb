module Textus
  module Handlers
    module Read
      module DiffEntry
        HANDLES = Dispatch::Contracts::DiffEntry
        NEEDS   = %i[file_store manifest schemas layout].freeze

        def self.call(command, _call, deps)
          reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
          proposal_env = reader.read(command.pending_key)
          proposal = proposal_env&.meta&.dig("proposal") or
            return Value::Result.failure(:proposal_error, "entry has no proposal block: #{command.pending_key}")
          target_key = proposal["target_key"] or
            return Value::Result.failure(:proposal_error, "proposal missing target_key")

          target_env = reader.read(target_key)

          body_diff = Textus::Diff.body(target_env&.body, proposal_env.body)
          meta_diff = Textus::Diff.meta(target_env&.meta&.dig("_meta") || {}, proposal_env.meta&.dig("_meta") || {})

          target_schema = target_schema_ref(target_key, deps)
          proposal_schema = proposal_env&.meta&.dig("_meta", "schema")
          schema_diff = if proposal_schema && target_schema != proposal_schema
                          Textus::Diff.schema({ "schema" => target_schema }, { "schema" => proposal_schema })
                        end

          result = { "pending_key" => command.pending_key, "target_key" => target_key }
          result["body"] = body_diff if body_diff
          result["meta"] = meta_diff if meta_diff
          result["schema"] = schema_diff if schema_diff
          result["summary"] = Textus::Diff.summary(result)

          Value::Result.success(result)
        end

        def self.target_schema_ref(key, deps)
          entry = deps.manifest.data.entries.find { |e| e.key == key }
          entry&.schema_ref
        end
      end
    end
  end
end
