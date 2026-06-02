module Textus
  class Manifest
    class Entry
      module Publish
        # Shared base for the two key-driven publish_each modes (EachFile,
        # EachDir). Owns the leaf enumeration, the `{...}` target templating, and
        # the per-leaf repo-escape guard. Subclasses implement `#publish_leaf`,
        # returning `{ written:, pruned: }`, and the discriminator half of
        # `#validate!`.
        class Each < Mode
          def publish(pctx, prefix: nil)
            leaves = []
            pruned = []
            pctx.manifest.resolver.enumerate(prefix: entry.key).each do |row|
              next unless row[:manifest_entry].equal?(entry)
              next if prefix && !row[:key].start_with?(prefix) && row[:key] != prefix

              target_abs = guarded_target(pctx, row)
              result = publish_leaf(row, target_abs, pctx)
              pruned.concat(result[:pruned])
              result[:written].each do |w|
                leaves << { "key" => row[:key], "source" => w["source"], "target" => w["target"] }
              end
            end

            { kind: :leaves, value: leaves, pruned: pruned }
          end

          # Expand this entry's publish_each template for a full leaf key.
          def target_for(full_key)
            entry_segs = entry.key.split(".")
            key_segs = full_key.split(".")
            raise UsageError.new("key '#{full_key}' is not under entry '#{entry.key}'") unless key_segs[0, entry_segs.length] == entry_segs

            remaining = key_segs[entry_segs.length..] || []
            Template.expand(
              entry.publish_each,
              "leaf" => remaining.join("/"),
              "basename" => remaining.last || "",
              "key" => full_key,
              "ext" => ext,
            )
          end

          private

          def guarded_target(pctx, row)
            target_rel = target_for(row[:key])
            target_abs = repo_abs(pctx, target_rel)
            return target_abs if inside_repo?(pctx, target_abs)

            raise Textus::PublishError.new(
              "entry '#{entry.key}': publish_each target '#{target_rel}' for key '#{row[:key]}' escapes repo root",
            )
          end

          def ext
            Textus::Entry.for_format(entry.format).extensions.first.to_s.sub(/^\./, "")
          end

          # publish_each shape rules common to file and directory leaves: a
          # String value with only known template vars. Returns the used vars so
          # subclasses can apply their discriminator rule.
          def validate_template_basics
            publish_each = entry.publish_each
            raise UsageError.new("entry '#{entry.key}': publish_each must be a string") unless publish_each.is_a?(String)

            used_vars = publish_each.scan(Template::VAR_RE).flatten
            unknown = used_vars - Template::KNOWN_VARS
            unless unknown.empty?
              raise UsageError.new(
                "entry '#{entry.key}': publish_each uses unknown template variable(s) " \
                "#{unknown.map { |v| "{#{v}}" }.join(", ")}. Known: #{Template::KNOWN_VARS.map { |v| "{#{v}}" }.join(", ")}.",
              )
            end

            used_vars
          end
        end
      end
    end
  end
end
