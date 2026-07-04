Textus.workflow "invariants-assembler" do
  on "artifacts.design.invariants"

  step :assemble do |_, ctx|
    resolver = ctx.manifest.resolver

    read_atoms = lambda do |prefix|
      resolver.enumerate(prefix: prefix, include_keyless: true)
              .reject { |row| row[:key] == prefix }
              .sort_by { |row| row[:key] }
              .filter_map { |row| ctx.read(row[:key]) }
              .uniq(&:key)
              .map { |env| { "key" => env.key, "slug" => env.key.split(".").last, "body" => env.body.to_s } }
    end

    goals = read_atoms.call("knowledge.loop.intent")
    rules = read_atoms.call("knowledge.loop.constraint.repo")

    { "content" => { "goals" => goals, "rules" => rules } }
  end
  publish to: "docs/design/invariants.md", template: "docs/design/invariants.erb"
end
