module Textus
  module UseCases
    module Read
      class ListKeys < Base
        handles Dispatch::Contracts::ListKeys
        needs :manifest, :file_system, :layout, :entry_index

        def call
          q      = @command.respond_to?(:q)      ? @command.q      : nil
          schema = @command.respond_to?(:schema) ? @command.schema : nil

          return sqlite_list(query: q, schema: schema, lane: @command.lane, prefix: @command.prefix) if @entry_index && (q || schema)

          manifest_list(prefix: @command.prefix, lane: @command.lane)
        end

        private

        def sqlite_list(query:, schema:, lane:, prefix:)
          rows = @entry_index.search(query:, schema:, lane:, prefix:)
          success((rows || []).map { |r| { "key" => r["key"], "lane" => r["lane"] } })
        end

        def manifest_list(prefix:, lane:)
          rows = @manifest.resolver.enumerate(prefix: prefix)
          rows = rows.select { |row| row[:manifest_entry].lane == lane } if lane
          success(rows.map do |row|
            { "key" => row[:key], "lane" => row[:manifest_entry].lane, "path" => row[:path] }
          end)
        end
      end
    end
  end
end
