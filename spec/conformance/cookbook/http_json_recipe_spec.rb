require "spec_helper"

# Proves the cookbook's HTTP-JSON recipe shape against the step surface: a custom
# fetch step delegates parsing to the built-in :json fetch step.
RSpec.describe "cookbook: http_json intake recipe" do
  let(:steps) { Textus::Step::RegistryStore.new }
  let(:caps) { Struct.new(:steps).new(steps) }

  before do
    Textus::Step::Builtin.register_all(steps)

    klass = Class.new(Textus::Step::Fetch) do
      def call(caps:, config:, args:, **)
        _ = config # the recipe reads config["url"]; the stub ignores it
        body = %({"name":"ada","role":"author"}) # stands in for Net::HTTP.get
        caps.steps.invoke(:fetch, :json, caps: caps,
                                         config: { "bytes" => body }, args: args)
      end
    end

    steps.register(klass.new.tap { |s| s.name = :http_json })
  end

  it "delegates to the built-in :json parser and yields YAML body" do
    result = steps.invoke(
      :fetch, :http_json, caps: caps,
                          config: { "url" => "https://example.test/u" }, args: nil
    )
    expect(result[:_meta]).to eq({})
    expect(YAML.safe_load(result[:body])).to eq("name" => "ada", "role" => "author")
  end
end
