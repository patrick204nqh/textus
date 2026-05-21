module Textus
  class CLI
    class Migrate < Verb
      # Does not need a store — the target manifest may still be textus/1.
      def self.needs_store? = false

      def call(_store)
        target = positional.shift or raise UsageError.new("migrate requires a target (e.g. 'v2')")
        raise UsageError.new("unknown migration target: #{target.inspect}; supported: v2") unless target == "v2"

        # Locate the .textus directory the same way Store.discover does.
        root = find_textus_root
        emit(Textus::MigrateV2.run(root))
      end

      private

      def find_textus_root
        explicit = ENV.fetch("TEXTUS_ROOT", nil)
        if explicit
          abs = File.expand_path(explicit)
          return abs if File.directory?(abs)

          raise IoError.new("no textus store at #{abs}")
        end

        dir = File.expand_path(@cwd)
        loop do
          candidate = File.join(dir, ".textus")
          return candidate if File.directory?(candidate) && File.exist?(File.join(candidate, "manifest.yaml"))

          parent = File.dirname(dir)
          break if parent == dir

          dir = parent
        end
        raise IoError.new("no .textus directory found from #{@cwd}")
      end
    end
  end
end
