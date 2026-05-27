require "timeout"

module Textus
  # Health check for a Textus store. Returns a JSON-friendly Hash envelope
  # with an `issues` array and a summary. Each issue is a Hash with
  # `code`, `level`, `subject`, `message`, and optionally `fix`.
  module Doctor
    LEVELS = %w[error warning info].freeze
    DOCTOR_CHECK_TIMEOUT_SECONDS = 2

    CHECKS = [
      Check::ProtocolVersion,
      Check::ManifestFiles,
      Check::Schemas,
      Check::SchemaParseError,
      Check::Templates,
      Check::Hooks,
      Check::IntakeRegistration,
      Check::IllegalKeys,
      Check::Sentinels,
      Check::AuditLog,
      Check::UnownedSchemaFields,
      Check::SchemaViolations,
      Check::RuleAmbiguity,
      Check::HandlerAllowlist,
      Check::RefreshLocks,
    ].freeze

    ALL_CHECKS = CHECKS.map(&:name_key).freeze

    module_function

    def run(store, checks: nil)
      selected_keys = checks ? Array(checks).map(&:to_s) : ALL_CHECKS
      unknown = selected_keys - ALL_CHECKS
      unless unknown.empty?
        raise UsageError.new(
          "unknown doctor check: #{unknown.first}. Valid checks: #{ALL_CHECKS.join(", ")}",
        )
      end

      selected = CHECKS.select { |c| selected_keys.include?(c.name_key) }
      issues = selected.flat_map { |c| c.new(store).call }
      issues.concat(run_registered_checks(store))

      summary = LEVELS.to_h { |l| [l, issues.count { |i| i["level"] == l }] }
      {
        "protocol" => Textus::PROTOCOL,
        "ok" => summary["error"].zero?,
        "issues" => issues,
        "summary" => summary,
      }
    end

    def run_registered_checks(store)
      out = []
      view = Application::Context.legacy(store: store)
      store.registry.rpc_names(:validate).each do |name|
        callable = store.registry.rpc_callable(:validate, name)
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
                                  fix: "fix the :validate hook in .textus/hooks/")
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

    private_class_method :run_registered_checks, :fail_issue
  end
end
