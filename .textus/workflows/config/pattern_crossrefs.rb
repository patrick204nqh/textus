# Validates that every pattern doc references a decision (ADR).
# This is a validation workflow — runs via `textus validate pattern-crossrefs`.
# Inspired by knowledge_pipeline_spec cross-reference check.

Textus.workflow "pattern-crossrefs" do
  on "knowledge.loop.judgment.engineering.**"

  check "adr-refs" do |ctx|
    body = ctx.read(ctx.key)&.body.to_s
    if body.match?(/ADR-\d+/)
      []
    else
      [{ "code" => "missing_decision_ref", "severity" => "info",
         "message" => "pattern entry #{ctx.key} does not reference a decision (ADR)" }]
    end
  end
end
