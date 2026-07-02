Textus.workflow "readme" do
  match "artifacts.docs.readme"

  step :assemble do |_, ctx|
    order = %w[intro concept body].each_with_index.to_h.freeze

    sections = ctx.container.read_family("knowledge.intent")
                  .select { |env| env.key.start_with?("knowledge.intent.readme-") }
                  .uniq(&:key)
                  .sort_by { |env| order.fetch(env.key.split(".").last.delete_prefix("readme-"), 99) }
                  .map { |env| { "key" => env.key, "body" => env.body.to_s } }

    { "content" => { "sections" => sections } }
  end
  publish to: "README.md", template: "docs/meta/readme.erb"
end
