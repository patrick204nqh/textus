module Textus
  module Handlers
    module Read
      class ListKeys
        def initialize(manifest:, job_store: nil)
          @manifest  = manifest
          @job_store = job_store
        end

        def call(command, _call)
          q      = command.respond_to?(:q)      ? command.q      : nil
          schema = command.respond_to?(:schema) ? command.schema : nil

          return sqlite_list(q: q, schema: schema, lane: command.lane, prefix: command.prefix) if @job_store && (q || schema)

          manifest_list(prefix: command.prefix, lane: command.lane)
        end

        private

        def sqlite_list(q:, schema:, lane:, prefix:) # rubocop:disable Naming/MethodParameterName
          rows = @job_store.search_entries(q: q, schema: schema, lane: lane, prefix: prefix)
          Value::Result.success((rows || []).map { |r| { "key" => r["key"], "lane" => r["lane"] } })
        end

        def manifest_list(prefix:, lane:)
          rows = @manifest.resolver.enumerate(prefix: prefix)
          rows = rows.select { |row| row[:manifest_entry].lane == lane } if lane
          Value::Result.success(rows.map do |row|
            { "key" => row[:key], "lane" => row[:manifest_entry].lane, "path" => row[:path] }
          end)
        end
      end
    end
  end
end
