module Textus
  # Single capability record handed to every use case. Replaces the
  # ReadCaps/WriteCaps/HookCaps trio from 0.26.x. Built once per Store
  # (see Store#initialize); Store delegates its readers to this record,
  # so this `Data.define` is the single source of truth for the field set.
  Container = Data.define(
    :manifest, :file_store, :schemas, :root,
    :audit_log, :steps, :gate
  )
end
