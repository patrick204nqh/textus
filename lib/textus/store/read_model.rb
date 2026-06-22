module Textus
  class Store
    class ReadModel
      def initialize(container)
        @container = container
      end

      def get(key)
        @container.compositor.read(key)
      end

      def list(prefix: nil, lane: nil)
        manifest = @container.manifest
        rows = manifest.resolver.enumerate(prefix: prefix)
        rows = rows.select { |row| row[:manifest_entry].lane == lane } if lane
        rows.map { |row| { "key" => row[:key], "lane" => row[:manifest_entry].lane, "path" => row[:path] } }
      end

      def where(key)
        manifest = @container.manifest
        res = manifest.resolver.resolve(key)
        mentry = res.entry
        { "protocol" => Textus::PROTOCOL, "key" => key, "lane" => mentry.lane, "owner" => mentry.owner, "path" => res.path }
      end

      def exists?(key)
        @container.compositor.exists?(key)
      end

      def uid(key)
        envelope = get(key)
        envelope&.uid
      end

      def audit(key: nil, lane: nil, role: nil, verb: nil, since: nil, seq_since: nil, correlation_id: nil, limit: nil)
        rows = @container.audit_log.scan(seq_since: seq_since, key: key, role: role, verb: verb,
                                          correlation_id: correlation_id, limit: limit)
        rows = rows.select do |row|
          next false if lane && !key_in_lane?(row["key"], lane)
          next false if since && (row["ts"].nil? || Time.parse(row["ts"]) < since)
          true
        end
        rows
      end

      def deps(key)
        entry = @container.manifest.data.entries.find { |e| e.key == key }
        deps = entry&.external? ? Array(entry.source&.sources).compact : []
        { "key" => key, "deps" => deps.uniq }
      end

      def rdeps(key)
        manifest = @container.manifest
        rdeps = manifest.data.entries.each_with_object([]) do |entry, acc|
          next unless entry.external?
          sources = Array(entry.source&.sources).compact
          acc << entry.key if sources.any? { |source| source == key || key.start_with?("#{source}.") }
        end
        { "key" => key, "rdeps" => rdeps }
      end

      def schema_for(key)
        manifest = @container.manifest
        mentry = manifest.resolver.resolve(key).entry
        schema = @container.schemas.fetch_or_nil(mentry.schema)
        { "protocol" => Textus::PROTOCOL, "key" => key, "schema_ref" => mentry.schema, "schema" => schema&.to_h }
      end

      def published
        @container.manifest.data.entries.reject { |entry| entry.publish_to.empty? }.map do |entry|
          { "key" => entry.key, "publish_to" => entry.publish_to }
        end
      end

      def rule_list
        list_fields = Textus::Manifest::Schema::FIELD_REGISTRY.select { |_, m| m[:in_rule_list] }.keys.freeze
        @container.manifest.rules.blocks.map do |block|
          row = { "match" => block.match }
          list_fields.each do |field|
            value = block.public_send(field)
            row[field.to_s] = serialize_field(field, value) unless value.nil?
          end
          row
        end
      end

      def rule_explain(key, detail: nil)
        manifest = @container.manifest
        detail ? explain_detail(manifest, key) : effective_rule(manifest, key)
      end

      def boot
        Textus::Boot.build(container: @container)
      end

      private

      def key_in_lane?(key, lane)
        mentry = @container.manifest.resolver.resolve(key).entry
        mentry && mentry.lane == lane
      rescue Textus::Error
        false
      end

      def serialize_field(field, value)
        case field
        when :retention then { "ttl_seconds" => value.ttl_seconds, "action" => value.action.to_s }
        when :react then value.to_h
        else value
        end
      end

      def effective_rule(manifest, key)
        lean_fields = Textus::Manifest::Schema::FIELD_REGISTRY
          .select { |_, m| m[:in_rule_explain].include?(:lean) }.keys.freeze
        set = manifest.rules.for(key)
        lean_fields.each_with_object({}) do |field, out|
          value = set.public_send(field)
          out[field.to_s] = lean_value(field, value) unless value.nil?
        end
      end

      def lean_value(field, value)
        case field
        when :retention then { "ttl_seconds" => value.ttl_seconds, "action" => value.action }
        when :react then value.to_h
        else value
        end
      end

      def explain_detail(manifest, key)
        detail_fields = Textus::Manifest::Schema::FIELD_REGISTRY
          .select { |_, m| m[:in_rule_explain].include?(:detail) }.keys.freeze
        effective_fields = detail_fields.select { |f| Textus::Manifest::Schema::FIELD_REGISTRY[f][:policy_class] }.freeze
        matching = manifest.rules.explain(key)
        winners = manifest.rules.for(key)
        {
          key: key,
          matched_blocks: matching.map do |block|
            { match: block.match }.merge(detail_fields.to_h { |f| [f, !block.public_send(f).nil?] })
          end,
          effective: effective_fields.to_h { |f| [f, effective_value(f, winners.public_send(f))] },
          guards: Textus::Gate::Auth::FLOOR.keys.to_h do |action|
            floor = Textus::Gate::Auth::FLOOR.fetch(action, [])
            rule = Array(manifest.rules.for(key).guard&.dig(action.to_s))
            [action, { floor: floor, rule: rule }]
          end,
        }
      end

      def effective_value(field, value)
        return nil if value.nil?
        case field
        when :retention then { ttl_seconds: value.ttl_seconds, action: value.action }
        when :react then value.to_h
        else value
        end
      end
    end
  end
end
