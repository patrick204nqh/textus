# frozen_string_literal: true

module Textus
  module Dispatch
    module Catalog
      module Events
        # Surface events — fired by Surfaces::RoleScope#dispatch_bound
        ENTRY_GET = "entry.get"
        ENTRY_PUT = "entry.put"
        ENTRY_DELETE = "entry.delete"
        ENTRY_MV = "entry.mv"
        ENTRY_ACCEPT = "entry.accept"
        ENTRY_REJECT = "entry.reject"
        ENTRY_PROPOSE = "entry.propose"
        ENTRY_LIST = "entry.list"
        ENTRY_BLAME = "entry.blame"
        ENTRY_AUDIT = "entry.audit"
        ENTRY_DEPS = "entry.deps"
        ENTRY_RDEPS = "entry.rdeps"
        ENTRY_WHERE = "entry.where"
        ENTRY_UID = "entry.uid"
        ENTRY_ENQUEUE = "entry.enqueue"

        # Pipeline events — fired by actions on completion
        ENTRY_WRITTEN = "entry.written"
        ENTRY_DELETED = "entry.deleted"
        ENTRY_FETCHED = "entry.fetched"
        ENTRY_DERIVED = "entry.derived"
        ENTRY_VALIDATED = "entry.validated"
        ENTRY_PUBLISHED = "entry.published"

        # Step events
        STEP_FETCH_COMPLETE = "step.fetch.complete"
        STEP_TRANSFORM_COMPLETE = "step.transform.complete"
        STEP_VALIDATE_PASSED = "step.validate.passed"
        STEP_VALIDATE_FAILED = "step.validate.failed"

        # Scheduled events — fired by watcher scheduler only
        SCHEDULED_FETCH = "scheduled.fetch"
        SCHEDULED_DRAIN = "scheduled.drain"
        SCHEDULED_RETENTION = "scheduled.retention"

        # System events
        SESSION_OPENED = "session.opened"
        SESSION_CLOSED = "session.closed"
        STORE_LOADED = "store.loaded"

        # Lookup: verb symbol -> surface event name
        VERB_EVENT = {
          get: ENTRY_GET,
          put: ENTRY_PUT,
          key_delete: ENTRY_DELETE,
          key_mv: ENTRY_MV,
          accept: ENTRY_ACCEPT,
          reject: ENTRY_REJECT,
          propose: ENTRY_PROPOSE,
          list: ENTRY_LIST,
          blame: ENTRY_BLAME,
          audit: ENTRY_AUDIT,
          deps: ENTRY_DEPS,
          rdeps: ENTRY_RDEPS,
          where: ENTRY_WHERE,
          uid: ENTRY_UID,
          enqueue: ENTRY_ENQUEUE,
        }.freeze
      end
    end
  end
end
