module Textus
  module Doctor
    class Check
      class Extensions < Check
        def call
          out = []
          dir = File.join(store.root, "extensions")
          return out unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.rb")).sort.each do |f| # rubocop:disable Lint/RedundantDirGlobSort
            registry = Hooks::Registry.new
            Textus.with_registry(registry) do
              load(f)
            end
          rescue StandardError, ScriptError => e
            out << {
              "code" => "extension.load_failed",
              "level" => "error",
              "subject" => File.basename(f),
              "message" => "#{e.class}: #{e.message}",
              "fix" => "open #{f} and fix the syntax/load error",
            }
          end
          out
        end
      end
    end
  end
end
