module Textus
  module Events
    ENTRY_WRITTEN   = "entry.written"
    ENTRY_DELETED   = "entry.deleted"
    ENTRY_RENAMED   = "entry.renamed"
    ENTRY_FETCHED   = "entry.fetched"
    ENTRY_DERIVED   = "entry.derived"
    ENTRY_VALIDATED = "entry.validated"
    ENTRY_PUBLISHED = "entry.published"
    PIPELINE_FAILED = "pipeline.failed"

    STEP_FETCH_COMPLETE     = "step.fetch.complete"
    STEP_TRANSFORM_COMPLETE = "step.transform.complete"
    STEP_VALIDATE_PASSED    = "step.validate.passed"
    STEP_VALIDATE_FAILED    = "step.validate.failed"

    STORE_LOADED   = "store.loaded"
    SESSION_OPENED = "session.opened"
    SESSION_CLOSED = "session.closed"
  end
end
