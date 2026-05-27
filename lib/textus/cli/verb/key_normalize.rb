module Textus
  class CLI
    class Verb
      class KeyNormalize < Verb
        command_name "normalize"
        parent_group Group::Key

        option :write, "--write"
        option :dry_run, "--dry-run"
        option :upgrade_manifest, "--upgrade-manifest"

        def call(store)
          if upgrade_manifest
            run_upgrade_manifest(store)
          else
            effective_write = write && !dry_run
            res = Textus::Application::Tools::MigrateKeys.run(store, write: effective_write || false)
            emit(res, exit_code: res["ok"] ? 0 : 1)
          end
        end

        private

        def run_upgrade_manifest(store)
          manifest_path = File.join(store.root, "manifest.yaml")
          orig = File.read(manifest_path)
          new_yaml = Textus::Application::Tools::MigrateManifestToKinds.upgrade_yaml(orig)

          if dry_run
            diff_lines = unified_diff(orig, new_yaml, manifest_path)
            emit({ "protocol" => PROTOCOL, "dry_run" => true, "diff" => diff_lines, "ok" => true }, exit_code: 0)
          else
            File.write(manifest_path, new_yaml)
            puts "upgraded manifest at #{manifest_path}"
            emit({ "protocol" => PROTOCOL, "upgraded" => manifest_path, "ok" => true }, exit_code: 0)
          end
        end

        def unified_diff(before, after, _path)
          before.lines.zip(after.lines).each_with_object([]) do |(a, b), acc|
            acc << "- #{a.chomp}" if a && a != b
            acc << "+ #{b.chomp}" if b && a != b
          end
        end
      end
    end
  end
end
