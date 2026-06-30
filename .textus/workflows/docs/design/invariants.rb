Textus.workflow "invariants-assembler" do
  match "artifacts.design.invariants"

  step :assemble do |_, ctx|
    read_atoms = lambda do |prefix|
      ctx.container.read_family(prefix, include_keyless: true)
         .reject { |env| env.key == prefix }
         .uniq(&:key)
         .sort_by(&:key)
         .map { |env| { "key" => env.key, "slug" => env.key.split(".").last, "body" => env.body.to_s } }
    end

    goals = read_atoms.call("knowledge.goals")
    rules = read_atoms.call("knowledge.rules")

    { "content" => { "goals" => goals, "rules" => rules } }
  end

  publish
end
