Textus.workflow "boot_refresh" do
  match "knowledge.boot"
  match "knowledge.loop.*"

  step :refresh do |_data, ctx|
    Textus::Protocol::Produce::Engine.converge(
      container: ctx.container, call: ctx.call, keys: ["artifacts.boot"],
    )
  end
end
