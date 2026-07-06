Textus.workflow "readme" do
  on "artifacts.docs.readme"

  step :assemble do |_, ctx|
    pitch = ctx.read("knowledge.loop.intent.0004-pitch")&.body.to_s
    idea = ctx.read("knowledge.loop.constraint.protocol.0015-idea")&.body.to_s
    quickstart = ctx.read("knowledge.loop.execution.runbook.0003-quickstart")&.body.to_s

    sections = [
      { "key" => "intro", "body" => pitch },
      { "key" => "concept", "body" => idea },
      { "key" => "body", "body" => quickstart },
    ].reject { |s| s["body"].nil? || s["body"].empty? }

    { "content" => { "sections" => sections } }
  end
  publish to: "README.md", template: "docs/meta/readme.erb"
end
