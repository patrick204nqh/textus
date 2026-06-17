# frozen_string_literal: true

module Textus
  class Manifest
    module Schema
      # Orchestrates structural validation (dry-schema Contract) then cross-field
      # semantic checks (Semantics). Public interface unchanged: Validator.validate!(raw).
      module Validator
        module_function

        def validate!(raw)
          raise BadManifest.new("manifest must be a hash") unless raw.is_a?(Hash)

          # Root unknown-key check before Contract so it fires even when lanes: is empty.
          Semantics.walk(raw, ROOT_KEYS, "$")

          result = Contract.call(raw)
          raise BadManifest.new(format_first_error(result.errors.messages)) unless result.success?

          raise BadManifest.new("manifest must declare lanes:") if Array(raw["lanes"]).empty?

          Semantics.check!(raw)
        end

        # Format the first dry-schema error to match the legacy path-prefixed style:
        # "unknown key 'x' at '$.lanes[0]'" for extra-key errors;
        # "manifest structure error at <path>: <msg>" for type/value errors.
        def format_first_error(messages)
          msg = messages.first
          return "manifest structure error: unknown" unless msg

          parent = format_path(msg.path[0..-2])
          key    = msg.path.last

          if msg.text == "is not allowed"
            "unknown key '#{key}' at '#{parent}'"
          else
            "manifest structure error at #{format_path(msg.path)}: #{msg.text}"
          end
        end

        def format_path(parts)
          "$" + Array(parts).map { |p| p.is_a?(Integer) ? "[#{p}]" : ".#{p}" }.join
        end
      end
    end
  end
end
