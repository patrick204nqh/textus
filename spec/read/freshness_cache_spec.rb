require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Read::Freshness, "verdict cache" do # rubocop:disable RSpec/DescribeMethod
  include_context "textus_store_fixture"
  include TextusSpecHelpers

  before do
    %w[zones/intake schemas hooks].each { |d| FileUtils.mkdir_p(File.join(root, d)) }
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: intake, kind: quarantine }
      entries:
        - key: intake.feed
          path: intake/feed.md
          zone: intake
          kind: intake
          intake:
            handler: noop
      rules:
        - { match: "intake.*", refresh: { ttl: 3600s, on_stale: warn } }
    YAML
    File.write(
      File.join(root, "zones/intake/feed.md"),
      "---\nkey: intake.feed\nlast_refreshed_at: \"#{Time.now.utc.iso8601}\"\n---\nhi\n",
    )
    File.write(File.join(root, "audit.log"), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:ctx)   { test_ctx(role: "automation") }

  it "memoizes evaluator output for unchanged (key, last_refreshed_at)" do
    counter = Class.new do
      attr_reader :calls

      def initialize
        @calls = 0
      end

      def call(_pol, _env, now:) # rubocop:disable Lint/UnusedMethodArgument
        @calls += 1
        Textus::Domain::Freshness::Verdict.fresh
      end
    end.new

    container = Textus::Container.from_store(store)
    fr = described_class.new(container: container, call: ctx, evaluator: counter)
    fr.call
    fr.call
    expect(counter.calls).to eq(1)
  end
end
