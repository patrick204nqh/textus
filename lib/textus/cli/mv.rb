module Textus
  class CLI
    class Mv < Verb
      prepend DeprecatedAliasMixin

      def self.deprecated_name = "mv"
      def self.replacement_path = "key mv"

      option :as_flag, "--as=ROLE"
      option :dry_run, "--dry-run"

      def call(store)
        old_key = positional.shift or raise UsageError.new("mv requires <old-key> <new-key>")
        new_key = positional.shift or raise UsageError.new("mv requires <old-key> <new-key>")
        role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
        emit(store.mv(old_key, new_key, as: role, dry_run: dry_run || false))
      end
    end
  end
end
