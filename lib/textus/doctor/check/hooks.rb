module Textus
  module Doctor
    class Check
      class Hooks < Check
        def call
          out = []
          dir = File.join(store.root, "hooks")
          return out unless File.directory?(dir)

          Dir.glob(File.join(dir, "*.rb")).sort.each do |f| # rubocop:disable Lint/RedundantDirGlobSort
            events = Textus::Hooks::EventBus.new
            rpc    = Textus::Hooks::RpcRegistry.new
            Textus.drain_hook_blocks
            begin
              load(f)
              Textus.drain_hook_blocks.each { |b| b.call(Textus::Hooks::Loader::Dsl.new(events: events, rpc: rpc)) }
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
