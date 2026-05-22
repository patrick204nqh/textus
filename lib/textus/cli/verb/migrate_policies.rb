module Textus
  class CLI
    class Verb
      class MigratePolicies < Verb
        option :dry_run, "--dry-run"

        def self.needs_store? = false

        def call(_store)
          root = @cwd
          changes = Textus::Migrate::Policies.new(root: root, dry_run: !dry_run.nil?).call
          emit({
                 "verb" => "migrate.policies",
                 "changes" => changes.map { |c| stringify(c) },
                 "dry_run" => !!dry_run,
               })
        end

        private

        def stringify(change)
          change.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
        end
      end
    end
  end
end
