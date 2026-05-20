require "fileutils"

module Textus
  module Init
    ZONES = %w[canon working intake pending derived].freeze

    DEFAULT_MANIFEST = <<~YAML
      version: textus/1
      zones:
        - { name: canon,   writable_by: [human] }
        - { name: working, writable_by: [human, ai, script] }
        - { name: intake,  writable_by: [script] }
        - { name: pending, writable_by: [ai, human] }
        - { name: derived, writable_by: [build] }
      entries:
        - { key: canon.identity, path: canon/identity.md, zone: canon, schema: null, owner: human:self }
        - { key: working.notes,  path: working/notes,     zone: working, schema: null, owner: human:self, nested: true }
    YAML

    def self.run(target_root)
      raise UsageError.new(".textus/ already exists at #{target_root}") if File.directory?(target_root)

      FileUtils.mkdir_p(File.join(target_root, "schemas"))
      FileUtils.mkdir_p(File.join(target_root, "templates"))
      FileUtils.mkdir_p(File.join(target_root, "extensions"))
      ZONES.each do |z|
        dir = File.join(target_root, "zones", z)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, ".gitkeep"), "")
      end
      File.write(File.join(target_root, "extensions", "README.md"), <<~MD)
        # Extensions

        Drop one Ruby file per extension. Four verbs are available:

        ```ruby
        Textus.action(:name)         { |config:, store:, args:| ... }
        Textus.reducer(:name)        { |rows:, config:|         ... }
        Textus.hook(:event, :name)   { |key:, envelope:, **kw|  ... }
        Textus.doctor_check(:name)   { |store:|                 ... }
        ```

        Events: :put, :delete, :refresh, :build, :accept.

        See SPEC.md §5.11 for the full contract.
      MD

      File.write(File.join(target_root, "manifest.yaml"), DEFAULT_MANIFEST)
      { "protocol" => PROTOCOL, "initialized" => target_root }
    end
  end
end
