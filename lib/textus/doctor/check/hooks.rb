module Textus
  module Doctor
    class Check
      class Hooks < Check
        def call
          out = []
          dir = File.join(store.root, "hooks")
          return out unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.rb")).sort.each do |f| # rubocop:disable Lint/RedundantDirGlobSort
            bus = Textus::Hooks::Bus.new
            Textus.drain_hook_blocks
            begin
              load(f)
              Textus.drain_hook_blocks.each { |b| b.call(bus) }
            end
          rescue StandardError, ScriptError => e
            out << {
              "code" => "hook.load_failed",
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
