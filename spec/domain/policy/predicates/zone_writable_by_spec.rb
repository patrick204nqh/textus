require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Textus::Domain::Policy::Predicates::ZoneWritableBy do
  # Default roles (no roles: block): human=[accept,propose], agent=[propose].
  # working is an origin zone, which requires the 'accept' capability.
  def build_manifest(dir)
    FileUtils.mkdir_p(File.join(dir, "zones", "working"))
    File.write(File.join(dir, "manifest.yaml"), <<~YAML)
      version: textus/3
      zones:
        - { name: working, kind: origin }
      entries:
        - { key: working.notes, path: working/notes.md, zone: working, kind: leaf }
    YAML
    Textus::Store.new(dir).manifest
  end

  def eval_for(role, target, manifest)
    Textus::Domain::Policy::Evaluation.new(
      actor: role, transition: :put, origin: nil,
      target: target, envelope: nil, snapshot: manifest
    )
  end

  it "passes when the role may write the target's zone" do
    Dir.mktmpdir do |root|
      manifest = build_manifest(File.join(root, ".textus"))
      expect(described_class.new.call(eval_for("human", "working.notes", manifest))).to be(true)
    end
  end

  it "fails for a role lacking the zone-kind's verb and raises WriteForbidden via #error" do
    Dir.mktmpdir do |root|
      manifest = build_manifest(File.join(root, ".textus"))
      pred = described_class.new
      e = eval_for("agent", "working.notes", manifest) # working is origin → needs 'accept'; agent has [propose]
      expect(pred.call(e)).to be(false)
      expect { raise pred.error(e) }.to raise_error(Textus::WriteForbidden) do |err|
        expect(err.code).to eq("write_forbidden")
        expect(err.message).to match(/capability 'accept'/) # post-0.31.0 capability-shaped message
      end
    end
  end
end
