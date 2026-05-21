require "fileutils"

module Textus
  module Init
    ZONES = %w[canon working intake pending derived].freeze

    DEFAULT_MANIFEST = <<~YAML
      version: textus/2
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
      FileUtils.mkdir_p(File.join(target_root, "hooks"))
      ZONES.each do |z|
        dir = File.join(target_root, "zones", z)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, ".gitkeep"), "")
      end
      File.write(File.join(target_root, "hooks", "README.md"), <<~MD)
        # Hooks

        Drop one Ruby file per hook. All hooks register through one DSL.
        Every handler receives `store:` as its first kwarg, then event-specific args.

        ```ruby
        Textus.hook(:fetch,  :name) { |store:, config:, args:|  ... }   # bring bytes in
        Textus.hook(:reduce, :name) { |store:, rows:, config:|  ... }   # transform rows
        Textus.hook(:check,  :name) { |store:|                  ... }   # doctor check
        Textus.hook(:put,    :name, keys: ["..."])                      # lifecycle listener
                                    { |store:, key:, envelope:| ... }
        ```

        Events: :fetch, :reduce, :check (rpc — return value used)
                :put, :delete, :refresh, :build, :accept (pub-sub — return discarded)

        See SPEC.md §5.10 for the full table.
      MD

      File.write(File.join(target_root, "manifest.yaml"), DEFAULT_MANIFEST)
      { "protocol" => PROTOCOL, "initialized" => target_root }
    end
  end
end
