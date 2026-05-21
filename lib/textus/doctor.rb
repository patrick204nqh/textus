require "digest"
require "json"
require "timeout"

module Textus
  # Health check for a Textus store. Returns a JSON-friendly Hash envelope
  # with an `issues` array and a summary. Each issue is a Hash with
  # `code`, `level`, `subject`, `message`, and optionally `fix`.
  module Doctor # rubocop:disable Metrics/ModuleLength -- 9 built-in checks + extension dispatch
    LEVELS = %w[error warning info].freeze
    DOCTOR_CHECK_TIMEOUT_SECONDS = 2
    ALL_CHECKS = %w[
      manifest_files schemas templates extensions illegal_keys
      sentinels audit_log unowned_schema_fields schema_violations
    ].freeze

    module_function

    def run(store, checks: nil)
      selected = checks ? Array(checks).map(&:to_s) : ALL_CHECKS
      unknown = selected - ALL_CHECKS
      unless unknown.empty?
        raise UsageError.new(
          "unknown doctor check: #{unknown.first}. Valid checks: #{ALL_CHECKS.join(", ")}",
        )
      end

      issues = run_builtin_checks(store, selected)
      issues.concat(run_registered_checks(store)) # extensions always run

      summary = LEVELS.to_h { |l| [l, issues.count { |i| i["level"] == l }] }
      {
        "protocol" => Textus::PROTOCOL,
        "ok" => summary["error"].zero?,
        "issues" => issues,
        "summary" => summary,
      }
    end

    def run_builtin_checks(store, selected)
      issues = []
      issues.concat(check_manifest_files(store))        if selected.include?("manifest_files")
      issues.concat(check_schemas(store))               if selected.include?("schemas")
      issues.concat(check_templates(store))             if selected.include?("templates")
      issues.concat(check_extensions(store))            if selected.include?("extensions")
      issues.concat(check_illegal_keys(store))          if selected.include?("illegal_keys")
      issues.concat(check_sentinels(store))             if selected.include?("sentinels")
      issues.concat(check_audit_log(store))             if selected.include?("audit_log")
      issues.concat(check_unowned_schema_fields(store)) if selected.include?("unowned_schema_fields")
      issues.concat(check_schema_violations(store))     if selected.include?("schema_violations")
      issues
    end

    # --- Checks -----------------------------------------------------------

    def check_manifest_files(store)
      out = []
      store.manifest.entries.each do |entry|
        next if entry.nested

        path = leaf_path_for(store, entry)
        next if File.exist?(path)

        out << {
          "code" => "manifest.missing_file",
          "level" => "info",
          "subject" => entry.key,
          "message" => "declared entry has no file on disk at #{path}",
          "fix" => "create the entry with 'textus put #{entry.key} --stdin --as=<role>' " \
                   "(or leave empty if not yet authored)",
        }
      end
      out
    end

    def check_schemas(store)
      out = []
      store.manifest.entries.each do |entry|
        next if entry.schema.nil?

        sp = File.join(store.root, "schemas", "#{entry.schema}.yaml")
        next if File.exist?(sp)

        out << {
          "code" => "schema.missing",
          "level" => "error",
          "subject" => entry.key,
          "message" => "schema '#{entry.schema}' not found at #{sp}",
          "fix" => "create the schema file or run 'textus schema init #{entry.schema} --from=<key>'",
        }
      end
      out
    end

    def check_templates(store)
      out = []
      store.manifest.entries.each do |entry|
        next if entry.template.nil?

        tp = File.join(store.root, "templates", entry.template)
        next if File.exist?(tp)

        out << {
          "code" => "template.missing",
          "level" => "error",
          "subject" => entry.key,
          "message" => "template '#{entry.template}' not found at #{tp}",
          "fix" => "create the file at #{tp} or update the entry's template: field",
        }
      end
      out
    end

    def check_extensions(store)
      out = []
      dir = File.join(store.root, "extensions")
      return out unless File.directory?(dir)

      Dir.glob(File.join(dir, "*.rb")).sort.each do |f| # rubocop:disable Lint/RedundantDirGlobSort
        registry = HookRegistry.new
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

    def check_illegal_keys(store)
      out = []
      store.manifest.entries.each do |entry|
        next unless entry.nested

        base = File.join(store.root, "zones", entry.path)
        next unless File.directory?(base)

        walk_nested(base) do |abs_path, is_dir|
          basename = File.basename(abs_path)
          stem = is_dir ? basename : basename.sub(/#{Regexp.escape(File.extname(basename))}\z/, "")
          next if stem.match?(Manifest::KEY_SEGMENT)

          proposed = Textus::MigrateKeys.normalize(stem)
          out << {
            "code" => "key.illegal",
            "level" => "error",
            "subject" => abs_path,
            "path" => abs_path,
            "proposed_key" => proposed,
            "message" => "illegal key segment '#{stem}' at #{abs_path}",
            "fix" => "run 'textus key migrate --dry-run' then '--write' to rename to '#{proposed}'",
          }
        end
      end
      out
    end

    def check_sentinels(store)
      out = []
      dir = File.join(store.root, "sentinels")
      return out unless File.directory?(dir)

      Dir.glob(File.join(dir, "**", "*.textus-managed.json")).each do |sp| # rubocop:disable Metrics/BlockLength
        begin
          data = JSON.parse(File.read(sp))
        rescue JSON::ParserError => e
          out << {
            "code" => "sentinel.parse_error",
            "level" => "warning",
            "subject" => sp,
            "message" => "sentinel is not valid JSON: #{e.message}",
            "fix" => "delete #{sp} and re-run 'textus build' to regenerate",
          }
          next
        end

        target = data["target"]
        recorded_sha = data["sha256"]

        if target.nil? || !File.exist?(target)
          out << {
            "code" => "sentinel.orphan",
            "level" => "warning",
            "subject" => sp,
            "message" => "sentinel target #{target.inspect} no longer exists",
            "fix" => "delete #{sp} (the published file is gone) or restore the target",
          }
          next
        end

        current_sha = Digest::SHA256.hexdigest(File.binread(target))
        next if recorded_sha.nil? || current_sha == recorded_sha

        out << {
          "code" => "sentinel.drift",
          "level" => "warning",
          "subject" => target,
          "message" => "published file at #{target} was modified out-of-band",
          "fix" => "re-run 'textus build' to overwrite, or copy the manual edit back into the store source",
        }
      end
      out
    end

    def check_audit_log(store)
      out = []
      path = File.join(store.root, "audit.log")
      return out unless File.exist?(path)

      File.foreach(path).with_index(1) do |line, lineno| # rubocop:disable Metrics/BlockLength
        stripped = line.chomp
        next if stripped.empty?

        if stripped.start_with?("{")
          begin
            JSON.parse(stripped)
          rescue JSON::ParserError => e
            out << {
              "code" => "audit.parse_error",
              "level" => "warning",
              "subject" => "#{path}:#{lineno}",
              "message" => "audit log line #{lineno} is invalid JSON: #{e.message}",
              "fix" => "inspect #{path} at line #{lineno} and remove the corrupted row",
            }
          end
        else
          # Legacy TSV (pre-0.5): read-only support retained for on-disk logs
          # written by older textus versions. Never written by current code.
          # Minimum 6 fields.
          fields = stripped.split("\t")
          next if fields.length >= 6

          out << {
            "code" => "audit.parse_error",
            "level" => "warning",
            "subject" => "#{path}:#{lineno}",
            "message" => "audit log line #{lineno} has #{fields.length} fields " \
                         "(expected >=6 for legacy TSV; consider migrating to NDJSON)",
            "fix" => "inspect #{path} at line #{lineno} and remove the corrupted row",
          }
        end
      end
      out
    end

    def check_unowned_schema_fields(store)
      out = []
      dir = File.join(store.root, "schemas")
      return out unless File.directory?(dir)

      Dir.glob(File.join(dir, "*.yaml")).sort.each do |sp| # rubocop:disable Lint/RedundantDirGlobSort
        schema = begin
          Schema.load(sp)
        rescue StandardError
          next
        end
        unowned = schema.fields.each_with_object([]) do |(name, spec), acc|
          acc << name if spec.is_a?(Hash) && spec["maintained_by"].nil?
        end
        next if unowned.empty?

        out << {
          "code" => "schema.unowned_fields",
          "level" => "info",
          "subject" => schema.name || File.basename(sp, ".yaml"),
          "message" => "schema has fields without maintained_by: #{unowned.join(", ")}",
          "fix" => "add 'maintained_by: <role>' to each field in #{sp} (optional but recommended)",
        }
      end
      out
    end

    def check_schema_violations(store)
      res = store.validate_all
      res["violations"].map do |v|
        fix = v["expected"] &&
              "field '#{v["field"]}' should be written by '#{v["expected"]}' (last writer: #{v["last_writer"]})"
        {
          "code" => v["code"],
          "level" => "error",
          "subject" => v["key"],
          "message" => v["message"] || "#{v["code"]} on #{v["key"]}",
          "fix" => fix,
        }.compact
      end
    end

    def run_registered_checks(store)
      out = []
      view = Store::View.new(store)
      store.registry.rpc_names(:check).each do |name|
        callable = store.registry.rpc_callable(:check, name)
        begin
          result = Timeout.timeout(DOCTOR_CHECK_TIMEOUT_SECONDS) { callable.call(store: view) }
          if result.is_a?(Array)
            out.concat(result.map { |h| h.transform_keys(&:to_s) })
          else
            out << fail_issue(name, code: "doctor_check.bad_return",
                                    message: "doctor_check '#{name}' returned #{result.class} (expected Array)",
                                    fix: "return an array of issue hashes from the doctor_check block")
          end
        rescue Timeout::Error
          out << fail_issue(name, code: "doctor_check.timeout",
                                  message: "doctor_check '#{name}' exceeded #{DOCTOR_CHECK_TIMEOUT_SECONDS}s",
                                  fix: "shorten the check or split it into smaller checks")
        rescue StandardError => e
          out << fail_issue(name, code: "doctor_check.failed",
                                  message: "#{e.class}: #{e.message}",
                                  fix: "fix the doctor_check block in .textus/extensions/")
        end
      end
      out
    end

    def fail_issue(name, code:, message:, fix:)
      {
        "code" => code,
        "level" => "error",
        "subject" => name.to_s,
        "message" => message,
        "fix" => fix,
      }
    end

    # --- Helpers ----------------------------------------------------------

    def leaf_path_for(store, entry)
      primary_ext = Entry.for_format(entry.format).extensions.first
      if File.extname(entry.path) == ""
        File.join(store.root, "zones", entry.path + primary_ext)
      else
        File.join(store.root, "zones", entry.path)
      end
    end

    def walk_nested(root, &block)
      Dir.each_child(root) do |name|
        abs = File.join(root, name)
        if File.directory?(abs)
          walk_nested(abs, &block)
          yield abs, true
        else
          yield abs, false
        end
      end
    end
  end
end
