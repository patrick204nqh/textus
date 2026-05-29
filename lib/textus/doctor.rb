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

    def run(session, checks: nil)
      container = Textus::Container.from_store_caps(
        session.read_caps, session.write_caps, session.hook_caps
      )
      run_via(container: container, role: session.ctx.role, checks: checks)
    end

    def run_via(container:, role: Textus::Role::DEFAULT, checks: nil) # rubocop:disable Lint/UnusedMethodArgument
      selected_keys = checks ? Array(checks).map(&:to_s) : ALL_CHECKS
      unknown = selected_keys - ALL_CHECKS
      unless unknown.empty?
        raise UsageError.new(
          "unknown doctor check: #{unknown.first}. Valid checks: #{ALL_CHECKS.join(", ")}",
        )
      end

      selected = CHECKS.select { |c| selected_keys.include?(c.name_key) }
      issues = selected.flat_map { |c| c.new(container).call }
      issues.concat(run_registered_checks(container))

      summary = LEVELS.to_h { |l| [l, issues.count { |i| i["level"] == l }] }
      {
        "protocol" => Textus::PROTOCOL,
        "ok" => summary["error"].zero?,
        "issues" => issues,
        "summary" => summary,
      }
    end

    def run_registered_checks(container)
      container.rpc.names(:validate).flat_map { |name| invoke_registered_check(container, name) }
    end

    # Build a write-caps-shaped struct so registered :validate hooks keep
    # the same caps: kwarg interface they had under the Session API.
    def caps_for(container)
      Struct.new(:manifest, :file_store, :schemas, :root, :audit_log, :events, :authorizer).new(
        container.manifest, container.file_store, container.schemas, container.root,
        container.audit_log, container.events, container.authorizer
      )
    end

    def invoke_registered_check(container, name)
      result = Timeout.timeout(DOCTOR_CHECK_TIMEOUT_SECONDS) do
        container.rpc.invoke(:validate, name, caps: caps_for(container))
      end
      return result.map { |h| h.transform_keys(&:to_s) } if result.is_a?(Array)

      [fail_issue(name, code: "doctor_check.bad_return",
                        message: "doctor_check '#{name}' returned #{result.class} (expected Array)",
                        fix: "return an array of issue hashes from the doctor_check block")]
    rescue Timeout::Error
      [fail_issue(name, code: "doctor_check.timeout",
                        message: "doctor_check '#{name}' exceeded #{DOCTOR_CHECK_TIMEOUT_SECONDS}s",
                        fix: "shorten the check or split it into smaller checks")]
    rescue StandardError => e
      [fail_issue(name, code: "doctor_check.failed",
                        message: "#{e.class}: #{e.message}",
                        fix: "fix the :validate hook in .textus/hooks/")]
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

    private_class_method :run_registered_checks, :invoke_registered_check, :fail_issue, :caps_for
  end
end
