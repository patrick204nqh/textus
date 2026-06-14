require "spec_helper"

RSpec.describe "Step loader subdirectory support" do
  def write_minimal_manifest(textus_root)
    File.write(
      File.join(textus_root, "manifest.yaml"),
      "version: textus/3\nlanes:\n  - { name: knowledge, kind: canon }\nentries: []\n",
    )
  end

  it "loads step files from nested subdirectories" do # rubocop:disable RSpec/ExampleLength
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "steps", "fetch"))
      FileUtils.mkdir_p(File.join(textus, "steps", "transform"))
      write_minimal_manifest(textus)

      File.write(
        File.join(textus, "steps", "fetch", "nested_intake.rb"),
        <<~RUBY,
          module Textus
            module Step
              class NestedIntakeFetch < Fetch
                def call(config:, args:, caps:, **) = { _meta: {}, body: "n" }
              end
            end
          end
        RUBY
      )

      File.write(
        File.join(textus, "steps", "transform", "nested_reduce.rb"),
        <<~RUBY,
          module Textus
            module Step
              class NestedReduceTransform < Transform
                def call(rows:, config:, **) = rows.reverse
              end
            end
          end
        RUBY
      )

      store = Textus::Store.new(textus)

      expect(store.steps.names(:fetch)).to include(:nested_intake)
      expect(store.steps.names(:transform)).to include(:nested_reduce)
    end
  end

  it "still loads flat steps (back-compat)" do
    Dir.mktmpdir do |root|
      textus = File.join(root, ".textus")
      FileUtils.mkdir_p(File.join(textus, "steps", "fetch"))
      write_minimal_manifest(textus)

      File.write(
        File.join(textus, "steps", "fetch", "flat.rb"),
        <<~RUBY,
          module Textus
            module Step
              class FlatFetch < Fetch
                def call(config:, args:, caps:, **) = { _meta: {}, body: "f" }
              end
            end
          end
        RUBY
      )

      store = Textus::Store.new(textus)
      expect(store.steps.names(:fetch)).to include(:flat)
    end
  end
end
