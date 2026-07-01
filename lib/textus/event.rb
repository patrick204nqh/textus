module Textus
  module Event
    EntryWritten     = Data.define(:key, :role, :etag_before, :etag_after, :occurred_at)
    EntryDeleted     = Data.define(:key, :role, :etag_before, :occurred_at)
    EntryMoved       = Data.define(:from_key, :to_key, :role, :etag_before, :etag_after, :occurred_at)
    ProposalOpened   = Data.define(:key, :proposal_key, :role, :occurred_at)
    ProposalAccepted = Data.define(:proposal_key, :target_key, :role, :occurred_at)
    ProposalRejected = Data.define(:proposal_key, :role, :occurred_at, :reason)
  end
end
