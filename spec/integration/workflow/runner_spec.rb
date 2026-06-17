RSpec.describe Textus::Workflow::Runner do
  include_context "textus_store_fixture"

  let(:store) do
    store_from_manifest(root, lanes: %w[knowledge feeds], manifest: <<~YAML)
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
        - { name: feeds, kind: machine }
      entries:
        - { key: knowledge.foo, path: knowledge/foo.md, lane: knowledge, kind: leaf}
        - key: artifacts.feeds.test
          kind: produced
          path: feeds/test.json
          lane: feeds
          source: { from: external, command: "true", sources: [] }
    YAML
  end
  let(:call) { Textus::Call.build(role: "automation") }

  def build_definition(pattern: "artifacts.**", &block)
    Textus::Workflow::DSL::Definition.new("test").tap do |d|
      d.match(pattern)
      d.instance_eval(&block) if block
    end
  end

  describe "#run" do
    it "threads data through steps in order" do
      defn = build_definition do
        step(:fetch)     { |_data, _ctx| %w[a b] }
        step(:transform) { |data, _ctx| data.map(&:upcase) }
      end

      runner = described_class.new(defn, container: store.container, call: call)
      allow(runner).to receive(:built_in_publish).and_return(nil)

      result = runner.run("artifacts.feeds.test")
      expect(result).to eq(%w[A B])
    end

    it "passes nil as data to the first step" do
      received = []
      defn = build_definition do
        step(:fetch) do |data, _ctx|
          received << data
          { content: "x" }
        end
      end

      runner = described_class.new(defn, container: store.container, call: call)
      allow(runner).to receive(:built_in_publish)
      runner.run("artifacts.feeds.test")

      expect(received.first).to be_nil
    end

    it "wraps step errors in Workflow::StepFailed" do
      defn = build_definition do
        step(:fetch) { |_data, _ctx| raise "exploded" }
      end

      runner = described_class.new(defn, container: store.container, call: call)
      expect { runner.run("artifacts.feeds.test") }
        .to raise_error(Textus::Workflow::StepFailed) do |e|
          expect(e.step_name).to eq(:fetch)
          expect(e.cause.message).to eq("exploded")
        end
    end

    it "calls publish block when one is declared" do
      published = []
      defn = build_definition do
        step(:fetch) { |_data, _ctx| { content: "result" } }
        publish { |data, _ctx| published << data }
      end

      runner = described_class.new(defn, container: store.container, call: call)
      runner.run("artifacts.feeds.test")

      expect(published.first).to eq({ content: "result" })
    end
  end
end
