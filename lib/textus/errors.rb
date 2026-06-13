module Textus
  class Error < StandardError
    attr_reader :code, :details, :exit_code, :hint

    def initialize(code, message, details: {}, exit_code: 1, hint: nil)
      super(message)
      @code = code
      @details = details
      @exit_code = exit_code
      @hint = hint
    end

    def to_envelope
      env = {
        "protocol" => Textus::PROTOCOL,
        "ok" => false,
        "code" => @code,
        "message" => message,
        "details" => @details,
      }
      env["hint"] = @hint if @hint
      env
    end
  end

  class UnknownKey < Error
    attr_reader :suggestions

    def initialize(key, suggestions: [])
      @suggestions = Array(suggestions)
      details = { "key" => key }
      details["suggestions"] = @suggestions unless @suggestions.empty?
      msg = "key '#{key}' does not resolve"
      msg += "; did you mean: #{@suggestions.join(", ")}" unless @suggestions.empty?
      hint =
        if @suggestions.empty?
          "run 'textus list --output=json' to see all keys"
        else
          "did you mean: #{@suggestions.join(", ")}"
        end
      super("unknown_key", msg, details: details, hint: hint)
    end
  end

  class BadFrontmatter < Error
    def initialize(path, m, hint: nil)
      hint ||= default_hint_for(path, m)
      super("bad_frontmatter", m, details: { "path" => path }, hint: hint)
    end

    private

    def default_hint_for(path, m)
      if m.is_a?(String) && (match = m.match(/name '([^']+)' does not match basename '([^']+)'/))
        name, basename = match.captures
        ext = File.extname(path)
        "rename the file to '#{name}#{ext}' or change _meta.name to '#{basename}'"
      else
        "open #{path} and check the YAML frontmatter for syntax errors"
      end
    end
  end

  class BadManifest < Error
    def initialize(m, hint: nil)
      super("bad_manifest", m, hint: hint)
    end
  end

  class BadContent < Error
    def initialize(path, m)
      super(
        "bad_content", m,
        details: { "path" => path },
        hint: "JSON/YAML parse failed; run the file through 'jq .' or 'yq .' to find the syntax error",
      )
    end
  end

  class SchemaViolation < Error
    def initialize(d)
      hint =
        if d.is_a?(Hash) && d["missing"]
          "add the missing field(s) to the entry's frontmatter: #{Array(d["missing"]).join(", ")}"
        elsif d.is_a?(Hash) && d["field"]
          "fix the field '#{d["field"]}' in the entry's frontmatter (#{d["reason"]})"
        end
      super("schema_violation", "schema violation", details: d, hint: hint)
    end
  end

  class WriteForbidden < Error
    def initialize(k, z, verb: nil, holders: nil)
      holders_str =
        if holders && !holders.empty?
          holders.join(", ")
        else
          "no declared role"
        end
      details = { "key" => k, "lane" => z }
      details["verb"] = verb if verb
      details["holders"] = holders if holders
      super(
        "write_forbidden",
        "writing '#{k}' (zone '#{z}') needs capability '#{verb}'",
        details: details,
        hint: "held by: #{holders_str}; pass --as=<role>",
      )
    end
  end

  class EtagMismatch < Error
    def initialize(k, w, g)
      super(
        "etag_mismatch", "etag mismatch on '#{k}'",
        details: { "key" => k, "wanted" => w, "got" => g },
        hint: "another writer changed this key; run 'textus get #{k}' to fetch the latest etag",
      )
    end
  end

  class IoError < Error
    def initialize(m) = super("io_error", m, exit_code: 64)
  end

  class BuildInProgress < Error
    def initialize(holder)
      super(
        "build_in_progress",
        "a textus maintenance pass is already running (#{holder})",
        details: { "holder" => holder },
        exit_code: 75,
        hint: "wait for the running maintenance pass to finish, or check for a recursive hook trigger"
      )
    end
  end

  class UsageError < Error
    def initialize(m, hint: nil) = super("usage", m, exit_code: 2, hint: hint)
  end

  class InvalidRole < Error
    def initialize(r, message: nil)
      super(
        "invalid_role",
        message || "role '#{r}' is not declared in any zone",
        details: { "role" => r },
        hint: message ? nil : "valid roles are declared in .textus/manifest.yaml under roles: (each with a can: list)",
      )
    end
  end

  class InvalidProjection < Error
    def initialize(m) = super("invalid_projection", m)
  end

  class TemplateError < Error
    def initialize(m, template_name: nil)
      hint =
        ("expected at .textus/templates/#{template_name}; add the file or update the entry's template: field" if template_name)
      super("template_error", m, hint: hint)
    end
  end

  class BadRender < Error
    def initialize(m, format: nil)
      hint =
        if format
          "the template rendered invalid #{format}; try rendering with mock data and parsing the output before re-running drain"
        else
          "the template rendered invalid content; try rendering with mock data and parsing the output before re-running drain"
        end
      super("bad_render", m, hint: hint)
    end
  end

  class PublishError < Error
    def initialize(m, target: nil)
      hint =
        ("file at #{target} wasn't published by textus; back it up and delete it, or move it under .textus/data/" if target)
      super("publish_error", m, details: target ? { "target" => target } : {}, hint: hint)
    end
  end

  class ProposalError < Error
    def initialize(m) = super("proposal_error", m)
  end

  class GuardFailed < Error
    def initialize(failed)
      # failed: [[predicate_name, reason], ...]
      rows = failed.map { |name, reason| { "predicate" => name, "reason" => reason } }
      names = failed.map(&:first)
      super(
        "guard_failed",
        "guard refused crossing: #{failed.map { |n, r| "#{n} (#{r})" }.join("; ")}",
        details: { "failed" => rows },
        hint: "run 'textus policy explain <key> --output=json' to see the full guard; " \
              "unmet: #{names.join(", ")}",
      )
    end
  end

  class FlagRenamed < Error
    def initialize(old_flag, new_flag)
      super(
        "flag_renamed",
        "#{old_flag} was renamed in textus/3 — use #{new_flag}",
        details: { "old" => old_flag, "new" => new_flag },
        hint: "Use #{new_flag} instead.",
        exit_code: 2,
      )
    end
  end

  class CursorExpired < Error
    attr_reader :requested, :min_available

    def initialize(requested:, min_available:)
      @requested = requested
      @min_available = min_available
      super(
        "cursor_expired",
        "audit cursor expired: requested seq=#{requested} but oldest available is #{min_available}; " \
        "call `textus boot` to re-orient and resume from latest_seq",
        details: { "requested" => requested, "min_available" => min_available },
        hint: "call `textus boot` to get the current latest_seq and resume from there",
      )
    end
  end
end
