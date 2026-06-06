require "spec_helper"
require "timeout"

# End-to-end proof of ADR 0087 Task 10: a real Store, booted exactly as in
# production (the subscriber is attached in Store#bootstrap_hooks), re-materializes
# derived dependents on a canon `put` with NO manual build/reconcile call.
RSpec.describe Textus::Ports::ReactiveMaterializeSubscriber do
  include_context "textus_store_fixture"

  # A canon source (knowledge.people) feeding a derived projection
  # (artifacts.catalogs.people) published to PEOPLE.md in the repo root.
  # `materialize_on_change:` flips the affected entry between sync/async.
  def build_store(materialize_on_change: nil)
    FileUtils.mkdir_p(File.join(root, "zones/knowledge/people"))
    FileUtils.mkdir_p(File.join(root, "zones/artifacts"))
    FileUtils.mkdir_p(File.join(root, "templates"))
    rules = if materialize_on_change
              <<~RULES
                rules:
                  - match: "artifacts.catalogs.people"
                    upkeep: { strategy: #{materialize_on_change} }
              RULES
            else
              ""
            end
    s = store_from_manifest(root, zones: %w[knowledge artifacts], manifest: <<~YAML)
      version: textus/3
      zones:
        - { name: knowledge, kind: canon }
        - { name: artifacts, kind: machine }
      entries:
        - { key: knowledge.people, path: knowledge/people, zone: knowledge, owner: human:self, kind: nested }

        - key: artifacts.catalogs.people
          kind: derived
          path: artifacts/catalogs/people.md
          zone: artifacts
          owner: automation:auto
          compute: { kind: projection, select: knowledge.people, pluck: [name, org], sort_by: name }
          template: people.mustache
          publish:
            to: [PEOPLE.md]
      #{rules}
    YAML
    File.write(File.join(root, "templates/people.mustache"),
               "{{#entries}}- {{name}} ({{org}})\n{{/entries}}")
    s
  end

  def published_path = File.join(File.dirname(root), "PEOPLE.md")

  context "with the sync materialize policy" do
    let(:store) { build_store(materialize_on_change: "sync") }

    it "updates the published artifact synchronously on put — fresh the instant put returns" do
      store.put("knowledge.people.alice",
                meta: { "name" => "alice", "org" => "x" }, body: "",
                role: "human")

      # No wait, no manual build: the inline materialize ran within the write.
      expect(File).to exist(published_path)
      expect(File.read(published_path)).to include("alice")
    end
  end

  context "with the async materialize policy (default)" do
    let(:store) { build_store } # no materialize rule → async default

    it "updates the published artifact via the deferred rebuild without a manual build" do
      store.put("knowledge.people.bob",
                meta: { "name" => "bob", "org" => "y" }, body: "",
                role: "human")

      # The write returned promptly; the async rebuild completes off-thread.
      # drain joins the tracked thread deterministically (the same mechanism
      # at_exit uses to guarantee completion before a CLI process exits).
      Textus::Maintenance::ReactiveMaterialize::AsyncRunner.drain

      Timeout.timeout(5) do
        sleep 0.02 until File.exist?(published_path) && File.read(published_path).include?("bob")
      end

      expect(File.read(published_path)).to include("bob")
    end
  end
end
