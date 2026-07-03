module Textus
  module Surface
    module MCP
      module DriftAnnotation
        module_function

        def apply(result, verb_name:, drifted:, is_read:, current_etag:, previous_etag:)
          result["contract_drifted"] = drifted if verb_name == :pulse

          if drifted && !is_read && verb_name != :boot
            result["_warning"] = "contract drifted (was #{previous_etag}, now #{current_etag}); call boot() to re-arm"
          end

          result
        end
      end
    end
  end
end
