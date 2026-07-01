module Textus
  module Handlers
    module Read
      module ListKeys
        HANDLES = Dispatch::Contracts::ListKeys
        NEEDS   = %i[manifest job_store].freeze

        def self.call(command, _call, deps)
          q      = command.respond_to?(:q)      ? command.q      : nil
          schema = command.respond_to?(:schema) ? command.schema : nil

          if deps.job_store && (q || schema)
            return sqlite_list(q: q, schema: schema, lane: command.lane, prefix: command.prefix,
                               deps: deps)
          end

          manifest_list(prefix: command.prefix, lane: command.lane, deps: deps)
        end

        def self.sqlite_list(q:, schema:, lane:, prefix:, deps:) # rubocop:disable Naming/MethodParameterName
          rows = deps.job_store.search_entries(q: q, schema: schema, lane: lane, prefix: prefix)
          Value::Result.success((rows || []).map { |r| { "key" => r["key"], "lane" => r["lane"] } })
        end

        def self.manifest_list(prefix:, lane:, deps:)
          rows = deps.manifest.resolver.enumerate(prefix: prefix)
          rows = rows.select { |row| row[:manifest_entry].lane == lane } if lane
          Value::Result.success(rows.map do |row|
            { "key" => row[:key], "lane" => row[:manifest_entry].lane, "path" => row[:path] }
          end)
        end
      end
    end
  end
end
