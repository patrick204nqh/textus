module Textus
  class Error < StandardError
    attr_reader :code, :details, :exit_code

    def initialize(code, message, details: {}, exit_code: 1)
      super(message)
      @code = code
      @details = details
      @exit_code = exit_code
    end

    def to_envelope
      {
        "protocol" => Textus::PROTOCOL,
        "ok" => false,
        "code" => @code,
        "message" => message,
        "details" => @details,
      }
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
      super("unknown_key", msg, details: details)
    end
  end

  class BadFrontmatter < Error
    def initialize(path, m) = super("bad_frontmatter", m, details: { "path" => path })
  end

  class BadContent < Error
    def initialize(path, m) = super("bad_content", m, details: { "path" => path })
  end

  class SchemaViolation < Error; def initialize(d) = super("schema_violation", "schema violation", details: d); end

  class WriteForbidden  < Error
    def initialize(k,
                   z)
      super("write_forbidden", "zone '#{z}' is not agent-writable for key '#{k}'", details: { "key" => k, "zone" => z })
    end
  end

  class EtagMismatch < Error
    def initialize(k, w, g) = super("etag_mismatch", "etag mismatch on '#{k}'", details: { "key" => k, "wanted" => w, "got" => g })
  end

  class IoError < Error
    def initialize(m) = super("io_error",          m,                              exit_code: 64)
  end

  class UsageError < Error; def initialize(m) = super("usage", m, exit_code: 2); end

  class InvalidRole < Error
    def initialize(r) = super("invalid_role",      "role '#{r}' is not declared in any zone", details: { "role" => r })
  end

  class InvalidProjection < Error; def initialize(m) = super("invalid_projection", m); end
  class TemplateError     < Error; def initialize(m) = super("template_error",    m); end
  class BadRender         < Error; def initialize(m) = super("bad_render",        m); end
  class PublishError      < Error; def initialize(m) = super("publish_error",     m); end
  class ProposalError     < Error; def initialize(m) = super("proposal_error",    m); end
end
