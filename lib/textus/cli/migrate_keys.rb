module Textus
  class CLI
    class MigrateKeysVerb < Verb
      option :write, "--write"
      option :dry_run, "--dry-run"

      def call(store)
        res = Textus::MigrateKeys.run(store, write: write || false)
        @stdout.puts(JSON.generate(res))
        res["ok"] ? 0 : 1
      end
    end
  end
end
