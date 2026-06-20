require "json"

module Textus
  module Surface
    class CLI
      # CLI-only input acquisition. Transforms entries of the uniform `inputs`
      # hash that declare a `source:`/`coerce:`, and builds `inputs` from a
      # `cli_stdin` envelope — so put/propose/migrate/rule_lint/audit need no
      # hand-authored CLI class (ADR 0068). MCP receives typed JSON, so these
      # never run there.
      module Sources
        module_function

        # Apply per-arg :file sources (value is a path -> file contents) and
        # :coerce callables to a by-name inputs hash. Returns a new hash.
        def acquire(spec, inputs)
          spec.args.each_with_object(inputs.dup) do |a, h|
            next unless h.key?(a.name)

            h[a.name] = File.read(h[a.name]) if a.source == :file
            h[a.name] = a.coerce.call(h[a.name]) if a.coerce
          end
        end

        # Parse a cli_stdin :json envelope into a by-name inputs hash, mapping
        # envelope keys (wire-names) to arg names.
        def from_stdin(spec, stream)
          return {} unless spec.cli_stdin == :json

          raw = stream.read.to_s
          return {} if raw.strip.empty? # no envelope piped -> required args surface as missing

          envelope = JSON.parse(raw)
          spec.args.each_with_object({}) do |a, h|
            h[a.name] = envelope[a.wire.to_s] if envelope.key?(a.wire.to_s)
          end
        end
      end
    end
  end
end
