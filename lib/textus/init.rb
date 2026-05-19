require "fileutils"

module Textus
  module Init
    def self.run(target_root, profile: "personal")
      raise UsageError.new(".textus/ already exists at #{target_root}") if File.directory?(target_root)

      FileUtils.mkdir_p(File.join(target_root, "schemas"))
      FileUtils.mkdir_p(File.join(target_root, "templates"))
      FileUtils.mkdir_p(File.join(target_root, "extensions"))
      File.write(File.join(target_root, "extensions", "README.md"), <<~MD)
        # Extensions

        Drop one Ruby file per extension. Three verbs are available:

        ```ruby
        Textus.fetcher(:name)        { |config:, store:| ... }
        Textus.reducer(:name)        { |rows:, config:| ... }
        Textus.hook(:event, :name)   { |key:, envelope:, store:, **kw| ... }
        ```

        Events: :put, :delete, :refresh, :build, :accept.

        See SPEC.md §5.11 for the full contract.
      MD
      profile_path = File.expand_path("../profiles/#{profile}.yaml", __FILE__)
      raise UsageError.new("unknown profile: #{profile}") unless File.exist?(profile_path)

      FileUtils.cp(profile_path, File.join(target_root, "manifest.yaml"))
      { "protocol" => PROTOCOL, "initialized" => target_root, "profile" => profile }
    end
  end
end
