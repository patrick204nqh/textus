module Textus
  module Protocol
    class StoreEngine
      module Delete
        module_function

        def call(key, deps:, if_etag: nil)
          path = Pipeline.resolve_path(key, deps)
          assert_exists!(key, path, deps)
          etag_before = Pipeline.check_etag(key, path, if_etag, deps.file_system)
          deps.file_system.delete(path)
          deps.entry_index.remove(key:)
          Pipeline.prune_parents(path, deps)
          append_audit(key, etag_before, deps)
          Pipeline.emit_event(deps, event_type: "entry.deleted",
                                    pending_key: key, emit_key: key)
          nil
        end

        def assert_exists!(key, path, deps)
          return if deps.file_system.exists?(path)

          raise Textus::UnknownKey.new(key,
                                       suggestions: deps.manifest.resolver.suggestions_for(key))
        end

        def append_audit(key, etag_before, deps)
          deps.audit_log.append(
            role: deps.call.role, verb: "key_delete", key:,
            etag_before:, etag_after: nil,
            correlation_id: deps.call.correlation_id
          )
        end
      end
    end
  end
end
