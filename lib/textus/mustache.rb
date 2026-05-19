module Textus
  module Mustache
    MAX_DEPTH = 8
    TAG = %r{\{\{(?<sigil>[#^/!&]?)\s*(?<name>[\w.-]+)\s*\}\}}

    def self.render(template, context, strict: false, depth: 0) # rubocop:disable Metrics/AbcSize
      raise TemplateError.new("template recursion depth #{depth} exceeded #{MAX_DEPTH}") if depth > MAX_DEPTH

      out = +""
      pos = 0
      while (m = template.match(TAG, pos))
        out << template[pos...m.begin(0)]
        case m[:sigil]
        when "!"
          # comment, skip
        when "#"
          section, new_pos = parse_section(template, m, m[:name])
          value = lookup(context, m[:name])
          out << render_section(section, value, context, strict, depth)
          pos = new_pos
          next
        when "^"
          section, new_pos = parse_section(template, m, m[:name])
          value = lookup(context, m[:name])
          if falsy?(value)
            raise TemplateError.new("template recursion depth #{depth + 1} exceeded #{MAX_DEPTH}") if depth + 1 > MAX_DEPTH

            out << render(section, context, strict: strict, depth: depth + 1)
          end
          pos = new_pos
          next
        when "/"
          raise TemplateError.new("unexpected closing tag #{m[:name]}")
        else
          val = lookup(context, m[:name])
          if val.nil?
            raise TemplateError.new("missing variable: #{m[:name]}") if strict
          else
            out << val.to_s
          end
        end
        pos = m.end(0)
      end
      out << template[pos..]
      out
    end

    def self.parse_section(template, open_match, name)
      open_re  = /\{\{#\s*#{Regexp.escape(name)}\s*\}\}|\{\{\^\s*#{Regexp.escape(name)}\s*\}\}/
      close_re = %r{\{\{/\s*#{Regexp.escape(name)}\s*\}\}}
      both = Regexp.union(open_re, close_re)
      depth = 1
      cursor = open_match.end(0)
      while (m = template.match(both, cursor))
        if m[0].start_with?("{{/")
          depth -= 1
          return [template[open_match.end(0)...m.begin(0)], m.end(0)] if depth.zero?
        else
          depth += 1
        end
        cursor = m.end(0)
      end
      raise TemplateError.new("unclosed section: #{name}")
    end

    def self.render_section(section, value, context, strict, depth)
      raise TemplateError.new("template recursion depth #{depth + 1} exceeded #{MAX_DEPTH}") if depth + 1 > MAX_DEPTH

      case value
      when Array
        value.map { |v| render(section, merge(context, v), strict: strict, depth: depth + 1) }.join
      when Hash
        render(section, merge(context, value), strict: strict, depth: depth + 1)
      when true
        render(section, context, strict: strict, depth: depth + 1)
      when false, nil
        # falsy in regular section: render nothing.
        # render_section is only called for inverted sections when falsy? is true at the call site,
        # so this branch is only hit for normal sections with falsy values.
        ""
      else
        render(section, context, strict: strict, depth: depth + 1)
      end || ""
    end

    def self.lookup(context, name)
      return context[name] if context.is_a?(Hash) && context.key?(name)

      name.split(".").reduce(context) do |acc, seg|
        return nil unless acc.is_a?(Hash)

        acc[seg]
      end
    end

    def self.merge(base, override)
      return base unless override.is_a?(Hash)

      base.merge(override)
    end

    def self.falsy?(v) = v.nil? || v == false || v == [] || v == ""
  end
end
