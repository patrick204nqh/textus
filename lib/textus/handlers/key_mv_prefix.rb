module Textus
  module Handlers
    class KeyMvPrefix
      def initialize(compositor:, manifest:)
        @compositor = compositor
        @manifest = manifest
      end

      def call(command, call)
        return Result.failure(:usage_error, "from_prefix and to_prefix required") if command.from_prefix.nil? || command.to_prefix.nil?

        list_cmd = Struct.new(:prefix, :lane, keyword_init: true).new(prefix: command.from_prefix, lane: nil)
        leaves = Handlers::ListKeys.new(manifest: @manifest).call(list_cmd, call).value

        if leaves.any? { |r| r["key"] == command.from_prefix }
          return Result.failure(:usage_error, "from_prefix '#{command.from_prefix}' is itself a leaf — use `mv` to rename a single key")
        end

        warnings = leaves.empty? ? ["no keys under #{command.from_prefix}"] : []
        steps = leaves.map do |row|
          old_key = row["key"]
          tail = old_key.delete_prefix("#{command.from_prefix}.")
          new_key = "#{command.to_prefix}.#{tail}"
          { "op" => "mv", "from" => old_key, "to" => new_key }
        end

        plan = Textus::Store::Jobs::Plan.new(steps: steps, warnings: warnings)
        return Result.success(plan) if command.dry_run

        steps.each do |step|
          move_cmd = Struct.new(:old_key, :new_key, :if_etag, :dry_run, keyword_init: true)
            .new(old_key: step["from"], new_key: step["to"], if_etag: nil, dry_run: false)
          Handlers::MoveKey.new(compositor: @compositor, manifest: @manifest).call(move_cmd, call)
        end
        Result.success(plan)
      end
    end
  end
end
