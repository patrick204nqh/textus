module Textus
  class CLI
    class Verb
      class Migrate < Verb
        def self.needs_store?
          false # operates on the .textus/ dir directly without instantiating Store
        end

        def parse(argv)
          @to = nil
          @dry_run = false
          argv.each do |tok|
            case tok
            when /\A--to=(.+)\z/ then @to = ::Regexp.last_match(1)
            when "--dry-run"     then @dry_run = true
            else
              raise UsageError.new("unknown arg to migrate: #{tok}")
            end
          end
        end

        def call(_store)
          raise UsageError.new("migrate requires --to=textus/3") unless @to == "textus/3"

          root = @cwd or raise UsageError.new("migrate requires a working directory")
          result = Textus::Migration::V3.run(root: root, dry_run: @dry_run)
          emit("ok" => result[:ok],
               "dry_run" => result[:dry_run],
               "hook_findings" => result[:hook_findings])
        end
      end
    end
  end
end
