module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        require_relative "move_pipeline/validate_keys"
        require_relative "move_pipeline/resolve_paths"
        require_relative "move_pipeline/assert_source_exists"
        require_relative "move_pipeline/assert_target_not_exists"
        require_relative "move_pipeline/check_cross_zone"
        require_relative "move_pipeline/ensure_uid"
        require_relative "move_pipeline/read_etag_before"
        require_relative "move_pipeline/check_etag"
        require_relative "move_pipeline/move_file"
        require_relative "move_pipeline/prune_parents"
        require_relative "move_pipeline/rewrite_basename"
        require_relative "move_pipeline/read_etag_after"
        require_relative "move_pipeline/read_envelope"
        require_relative "move_pipeline/append_audit"
        require_relative "move_pipeline/reindex_entry"
        require_relative "move_pipeline/emit_workflow_event"

        VALIDATION_STEPS = [
          ValidateKeys,
          ResolvePaths,
          AssertSourceExists,
          AssertTargetNotExists,
          CheckCrossZone,
          EnsureUid,
          ReadEtagBefore,
          CheckEtag,
        ].freeze

        MUTATE_STEPS = [
          MoveFile,
          PruneParents,
          RewriteBasename,
          ReadEtagAfter,
          ReadEnvelope,
          AppendAudit,
          EmitWorkflowEvent,
          ReindexEntry,
        ].freeze

        def self.call(from_key:, to_key:, deps:, if_etag: nil, dry_run: false)
          ctx = Pipeline::MoveContext.new(
            from_key:, to_key:, if_etag:,
            from_path: nil, to_path: nil,
            from_entry: nil, to_entry: nil,
            etag_before: nil, etag_after: nil, envelope: nil, dry_run:
          )
          steps = dry_run ? VALIDATION_STEPS : VALIDATION_STEPS + MUTATE_STEPS
          steps.reduce(ctx) { |c, step| step.call(c, deps) }
        end
      end
    end
  end
end
