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

    HOOKS_README = <<~MD
      # Hooks

      Drop one Ruby file per hook. All hooks register through one DSL.
      Files anywhere under `.textus/hooks/` (including subdirectories) are loaded at
      startup in alphabetical order by full path. Subdirectory names are organizational
      only — the registered event and name come from the DSL call, not the file path.

      ## Per-event sugar (preferred)

      ```ruby
      Textus.intake(:my_source) do |config:, args:, **|
        { _meta: { "last_refreshed_at" => Time.now.utc.iso8601 }, body: "…" }
      end

      Textus.reduce(:my_source) { |rows:, **| rows.map { |r| r.merge(processed: true) } }
      Textus.check(:my_check)   { |store:, **| { ok: true } }
      Textus.put(:my_listener, keys: ["working.*"]) { |key:, envelope:, **| }

      # Run a side-effect every time textus writes a file to your repo:
      Textus.published(:notify) do |key:, target:, **|
        warn "wrote \#{target} (from \#{key})"
      end
      ```

      The intake handler above is paired with the manifest:

      ```yaml
      - key: working.foo
        intake:
          handler: my_source
          ttl: 10m
          on_stale: timed_sync   # warn | sync | timed_sync (default: warn)
      ```

      ## Low-level primitive (always available)

      ```ruby
      Textus.hook(:intake, :name) { |store:, config:, args:|  ... }   # bring bytes in
      Textus.hook(:reduce, :name) { |store:, rows:, config:|  ... }   # transform rows
      Textus.hook(:check,  :name) { |store:|                  ... }   # doctor check
      Textus.hook(:put,    :name, keys: ["..."])                      # lifecycle listener
                                  { |store:, key:, envelope:| ... }
      ```

      Events: :intake, :reduce, :check (rpc — return value used)
              :put, :deleted, :refreshed, :built, :accepted, :published,
              :mv, :reject, :loaded,
              :refresh_started, :refresh_failed, :refresh_detached (pub-sub — return discarded)

      See SPEC.md §5.10 for the full table.
    MD

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
      File.write(File.join(target_root, "hooks", "README.md"), HOOKS_README)
      File.write(File.join(target_root, "manifest.yaml"), DEFAULT_MANIFEST)
      { "protocol" => PROTOCOL, "initialized" => target_root }
    end
  end
end
