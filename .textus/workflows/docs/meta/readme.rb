Textus.workflow "readme" do
  match "artifacts.docs.readme"

  step :assemble do |_, ctx|
    order = %w[intro concept body].each_with_index.to_h.freeze

    sections = ctx.container.read_family("knowledge.readme")
                  .reject { |env| env.key == "knowledge.readme" }
                  .uniq(&:key)
                  .sort_by { |env| order.fetch(env.key.split(".").last, 99) }
                  .map { |env| { "key" => env.key, "body" => env.body.to_s } }

    { "content" => { "sections" => sections } }
  end

  publish
end
