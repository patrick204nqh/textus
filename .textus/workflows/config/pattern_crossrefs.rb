# Validates that every pattern doc references a decision (ADR).
# This is a validation workflow — runs via `textus validate pattern-crossrefs`.
# Inspired by knowledge_pipeline_spec cross-reference check.

Textus.workflow "pattern-crossrefs" do
  match "knowledge.patterns.**"

  validate :check_refs do |_data, ctx|
    reader = Textus::Store::Entry::Reader.new(
      file_store: ctx.container.file_store,
      manifest: ctx.container.manifest,
      layout: ctx.container.layout
    )
    body = reader.read(ctx.key)&.body.to_s
    unless body.match?(/ADR-\d+/)
      [{ "code" => "missing_decision_ref", "severity" => "info",
         "message" => "pattern entry #{ctx.key} does not reference a decision (ADR)" }]
    else
      []
    end
  end
end
