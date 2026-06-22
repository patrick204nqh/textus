module Textus
  module Handlers
    class KeyDeletePrefix
      def initialize(compositor:, manifest:)
        @compositor = compositor
        @manifest = manifest
      end

      def call(command, call)
        return Result.failure(:usage_error, "prefix required") if command.prefix.nil? || command.prefix.empty?

        list_cmd = Struct.new(:prefix, :lane, keyword_init: true).new(prefix: command.prefix, lane: nil)
        leaves = Handlers::ListKeys.new(manifest: @manifest).call(list_cmd, call).value

        warnings = leaves.empty? ? ["no keys under #{command.prefix}"] : []
        steps = leaves.map { |row| { "op" => "delete", "key" => row["key"] } }

        plan = Textus::Store::Jobs::Plan.new(steps: steps, warnings: warnings)
        return Result.success(plan) if command.dry_run

        steps.each do |step|
          delete_cmd = Struct.new(:key, :if_etag, keyword_init: true).new(key: step["key"], if_etag: nil)
          Handlers::DeleteKey.new(compositor: @compositor).call(delete_cmd, call)
        end
        Result.success(plan)
      end
    end
  end
end
