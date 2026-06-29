module Textus
  module Dispatch
    module Contracts
      GetEntry = Data.define(:key)

      PutEntry = Data.define(:key, :meta, :body, :content, :if_etag)

      ListKeys = Data.define(:prefix, :lane)

      DeleteKey = Data.define(:key, :if_etag)

      MoveKey = Data.define(:old_key, :new_key, :if_etag, :dry_run)

      ProposeEntry = Data.define(:key, :meta, :body, :content)

      AcceptProposal = Data.define(:pending_key)

      RejectProposal = Data.define(:pending_key)

      EnqueueJob = Data.define(:type, :args)

      AuditEntries = Data.define(:key, :lane, :role, :verb, :since, :seq_since, :correlation_id, :limit)

      PulseEntries = Data.define(:since)

      BlameEntry = Data.define(:key, :limit)

      WhereEntry = Data.define(:key)

      UidEntry = Data.define(:key)

      DepsEntry = Data.define(:key)

      RdepsEntry = Data.define(:key)

      BootStore = Data.define

      DoctorStore = Data.define(:checks)

      PublishedEntries = Data.define

      RuleExplain = Data.define(:key, :detail)

      RuleList = Data.define

      SchemaEnvelope = Data.define(:key)

      DrainStore = Data.define(:prefix, :lane)

      IngestEntry = Data.define(:kind, :slug, :url, :path, :lane, :label)

      JobsAction = Data.define(:state, :action, :job_id)

      RuleLint = Data.define(:candidate_yaml)

      DataMv = Data.define(:from, :to, :dry_run)

      KeyMvPrefix = Data.define(:from_prefix, :to_prefix, :dry_run)

      KeyDeletePrefix = Data.define(:prefix, :dry_run)
    end
  end
end
