require "yaml"

module Textus
  module Migration
    module V3
      class ManifestRewriter
        ACTOR_RENAMES = { "ai" => "agent", "script" => "runner", "build" => "builder" }.freeze
        ZONE_RENAMES  = { "inbox" => "intake" }.freeze

        def self.rewrite(yaml_text)
          doc = YAML.safe_load(yaml_text, aliases: false)
          rewrite_doc!(doc)
          YAML.dump(doc)
        end

        def self.rewrite_doc!(doc)
          doc["version"] = "textus/3"
          rewrite_zones!(doc)
          rewrite_entries!(doc)
          rewrite_rules!(doc)
          doc
        end

        def self.rewrite_zones!(doc)
          Array(doc["zones"]).each do |z|
            z["name"] = ZONE_RENAMES.fetch(z["name"], z["name"]) if z["name"]
            if z.key?("writable_by")
              z["write_policy"] = rename_actors(Array(z.delete("writable_by")))
            elsif z.key?("write_policy")
              z["write_policy"] = rename_actors(Array(z["write_policy"]))
            end
            z["read_policy"] = Array(z.delete("readable_by")) if z.key?("readable_by")
            z["read_policy"] ||= ["all"]
          end
        end

        def self.rewrite_entries!(doc)
          Array(doc["entries"]).each do |e|
            e["zone"] = ZONE_RENAMES.fetch(e["zone"], e["zone"]) if e["zone"]
            e["key"]   = rewrite_key(e["key"]) if e["key"]
            e["owner"] = rewrite_owner(e["owner"]) if e["owner"]
            rewrite_compute!(e)
          end
        end

        def self.rewrite_rules!(doc)
          if (legacy = doc.delete("policies"))
            doc["rules"] = legacy
          end
          Array(doc["rules"]).each do |r|
            r["match"] = rewrite_key(r["match"]) if r["match"]
            r["intake_handler_allowlist"] = r.delete("handler_allowlist") if r.key?("handler_allowlist")
            if (legacy_pr = r.delete("promote_requires"))
              r["promotion"] = { "requires" => legacy_pr }
            end
          end
        end

        def self.rewrite_compute!(entry)
          # If already-textus/3 form is present, just rename reduce→transform inside.
          if entry["compute"].is_a?(Hash) && entry["compute"].key?("reduce")
            entry["compute"]["transform"] = entry["compute"].delete("reduce")
          end
          # Convert legacy projection:
          if (proj = entry.delete("projection"))
            new_compute = proj.dup.merge("kind" => "projection")
            new_compute["transform"] = new_compute.delete("reduce") if new_compute.key?("reduce")
            entry["compute"] = new_compute
          end
          # Convert legacy generator:
          if (gen = entry.delete("generator"))
            entry["compute"] = gen.dup.merge("kind" => "external")
          end
        end

        def self.rewrite_key(key)
          parts = key.to_s.split(".")
          parts[0] = ZONE_RENAMES.fetch(parts[0], parts[0]) if parts.any?
          parts.join(".")
        end

        def self.rewrite_owner(owner)
          return owner if owner.nil?

          first, *rest = owner.to_s.split(":")
          first = ACTOR_RENAMES.fetch(first, first)
          rest = rest.map { |r| ACTOR_RENAMES.fetch(r, r) }
          rest.empty? ? first : ([first] + rest).join(":")
        end

        def self.rename_actors(arr)
          arr.map { |a| ACTOR_RENAMES.fetch(a.to_s, a.to_s) }
        end
      end
    end
  end
end
