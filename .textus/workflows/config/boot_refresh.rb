Textus.workflow "boot_refresh" do
  match "knowledge.boot"
  match "knowledge.loop.**"

  step :refresh do |_data, ctx|
    Textus::Protocol::Produce::Engine.converge(
      container: ctx.container, call: ctx.call, keys: ["artifacts.boot"],
    )
  end

  step :doctor do |_data, ctx|
    Textus::Protocol::Produce::Engine.converge(
      container: ctx.container, call: ctx.call,
      keys: %w[
        artifacts.doctor.manifest-files
        artifacts.doctor.protocol-version
        artifacts.doctor.schema-parse-error
        artifacts.doctor.illegal-keys
        artifacts.doctor.sentinels
        artifacts.doctor.audit-log
        artifacts.doctor.schema-violations
        artifacts.doctor.proposal-targets
        artifacts.doctor.generator-drift
        artifacts.doctor.raw-asset-paths
        artifacts.doctor.scratchpad-sources
        artifacts.doctor.stale-reviewed-stamp
        artifacts.doctor.cursor-retention
        artifacts.doctor.publish-tree-overlap
        artifacts.doctor.loop-shape
        artifacts.doctor.naming-check
      ],
    )
  end
end
