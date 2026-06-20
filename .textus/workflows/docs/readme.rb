Textus.workflow "readme" do
  match "artifacts.docs.readme"

  step :assemble do |_, ctx|
    order = %w[intro concept body].each_with_index.to_h.freeze

    rows = ctx.container.manifest.resolver
              .enumerate(prefix: "knowledge.readme")
              .reject { |r| r[:key] == "knowledge.readme" }
              .uniq { |r| r[:key] }
              .sort_by { |r| order.fetch(r[:key].split(".").last, 99) }

    sections = rows.map do |r|
      env = Textus::Action::Get.new(key: r[:key])
              .call(container: ctx.container, call: ctx.call)
      { "key" => r[:key], "body" => env.body.to_s }
    end

    { "content" => { "sections" => sections } }
  end

  publish
end
