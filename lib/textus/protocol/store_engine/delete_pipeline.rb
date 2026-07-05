module Textus
  module Protocol
    class StoreEngine
      module DeletePipeline
        require_relative "delete_pipeline/resolve_path"
        require_relative "delete_pipeline/assert_exists"
        require_relative "delete_pipeline/check_etag"
        require_relative "delete_pipeline/delete_file"
        require_relative "delete_pipeline/prune_parents"
        require_relative "delete_pipeline/append_audit"
        require_relative "delete_pipeline/deindex_entry"
        require_relative "delete_pipeline/emit_workflow_event"

        STEPS = [
          ResolvePath,
          AssertExists,
          CheckEtag,
          DeleteFile,
          PruneParents,
          AppendAudit,
          EmitWorkflowEvent,
          DeindexEntry,
        ].freeze

        def self.call(key, deps:, if_etag: nil)
          ctx = Pipeline::DeleteContext.new(key:, if_etag:, path: nil, etag_before: nil)
          STEPS.reduce(ctx) { |c, step| step.call(c, deps) }
          nil
        end
      end
    end
  end
end
