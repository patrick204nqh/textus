module Textus
  # Health check for a Textus store. Returns a JSON-friendly Hash envelope
  # with an `issues` array and a summary. Each issue is a Hash with
  # `code`, `level`, `subject`, `message`, and optionally `fix`.
  module Doctor
    LEVELS = %w[error warning info].freeze

    CHECKS = [
      Check::ProtocolVersion,
      Check::ManifestFiles,
      Check::Schemas,
      Check::SchemaParseError,
      Check::Templates,
      Check::IllegalKeys,
      Check::Sentinels,
      Check::AuditLog,
      Check::UnownedSchemaFields,
      Check::SchemaViolations,
      Check::RuleAmbiguity,
      Check::OrphanedPublishTargets,
      Check::PublishTreeIndexOverlap,
      Check::ProposalTargets,
      Check::GeneratorDrift,
      Check::RawAssetPaths,
      Check::ScratchpadSources,
      Check::StaleReviewedStamp,
      Check::CursorRetention,
    ].freeze

    ALL_CHECKS = CHECKS.map(&:name_key).freeze

    module_function

    def build(container:, checks: nil, role: Textus::Value::Role::DEFAULT)
      selected_keys = checks ? Array(checks).map(&:to_s) : ALL_CHECKS
      unknown = selected_keys - ALL_CHECKS
      unless unknown.empty?
        raise UsageError.new(
          "unknown doctor check: #{unknown.first}. Valid checks: #{ALL_CHECKS.join(", ")}",
        )
      end

      selected = CHECKS.select { |c| selected_keys.include?(c.name_key) }
      issues = selected.flat_map { |c| c.new(container, role:).call }

      summary = LEVELS.to_h { |l| [l, issues.count { |i| i["level"] == l }] }
      {
        "protocol" => Textus::PROTOCOL,
        "ok" => summary["error"].zero?,
        "issues" => issues,
        "summary" => summary,
      }
    end
  end
end
