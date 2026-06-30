Textus.workflow "invariants-assembler" do
  match "artifacts.design.invariants"

  step :assemble do |_, ctx|
    require "digest"

    read_atoms = lambda do |prefix|
      ctx.container.read_family(prefix, include_keyless: true)
         .reject { |env| env.key == prefix }
         .uniq(&:key)
         .sort_by(&:key)
         .map { |env| { "key" => env.key, "slug" => env.key.split(".").last, "body" => env.body.to_s } }
    end

    goals = read_atoms.call("knowledge.goals")
    rules = read_atoms.call("knowledge.rules")

    canonical = (goals + rules).map { |e| "#{e["key"]}\n#{e["body"]}" }.join("\n---\n")
    uid = Digest::SHA1.hexdigest(canonical)[0, 16]

    { "_meta" => { "uid" => uid }, "content" => { "goals" => goals, "rules" => rules } }
  end

  publish
end
