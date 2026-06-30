Textus.workflow "invariants-assembler" do
  match "artifacts.design.invariants"

  step :assemble do |_, ctx|
    require "digest"

    read_atoms = lambda do |prefix|
      ctx.container.manifest.resolver
         .enumerate(prefix: prefix, include_keyless: true)
         .reject { |r| r[:key] == prefix }
         .uniq { |r| r[:key] }
         .sort_by { |r| r[:key] }
         .map do |r|
           env = ctx.container.reader.read(r[:key])
           { "key" => r[:key], "slug" => r[:key].split(".").last, "body" => env.body.to_s }
         end
    end

    goals = read_atoms.call("knowledge.goals")
    rules = read_atoms.call("knowledge.rules")

    canonical = (goals + rules).map { |e| "#{e["key"]}\n#{e["body"]}" }.join("\n---\n")
    uid = Digest::SHA1.hexdigest(canonical)[0, 16]

    { "_meta" => { "uid" => uid }, "content" => { "goals" => goals, "rules" => rules } }
  end

  publish
end
