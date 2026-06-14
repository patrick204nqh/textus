# frozen_string_literal: true

module Textus
  module Action
    class KeyMv < WriteVerb
      extend Textus::Contract::DSL

      verb :key_mv
      summary "Rename one entry (same zone + format). Refuses if the target exists. Single-key, lower blast radius than key_mv_prefix."
      surfaces :cli, :mcp
      cli "key mv"
      arg :old_key, String, required: true, positional: true,
                            description: "current dotted key"
      arg :new_key, String, required: true, positional: true,
                            description: "new dotted key (must be the same zone and format as old_key)"
      arg :dry_run, :boolean,
          description: "when true, returns the planned move (from/to paths, uid) without applying it; " \
                       "defaults to false, so omitting it applies the move immediately " \
                       "(unlike the bulk key_mv_prefix, which defaults to a dry-run plan)"

      BURN = :sync

      def initialize(old_key:, new_key:, dry_run: false)
        super()
        @old_key = old_key
        @new_key = new_key
        @dry_run = dry_run
      end

      def args
        {
          old_key: @old_key,
          new_key: @new_key,
          dry_run: @dry_run,
        }
      end

      def call(container:, call:)
        run_with_cascade(cascade_target_key, container:, call:) do
          execute_move(container, call)
        end
      end

      private

      def cascade_target_key
        @dry_run ? nil : @new_key
      end

      def execute_move(container, call)
        old_res, new_res = prepare(container, call)
        return dry_run_result(container, old_res, new_res) if @dry_run

        envelope = apply_move(container, call, old_res, new_res)
        publish_rename(container, call, envelope)
        success_result(old_res, new_res, envelope)
      end

      def apply_move(container, call, old_res, new_res)
        ensure_uid!(container, call, old_res.entry)
        writer(container, call).move(
          from_key: @old_key,
          to_key: @new_key,
          new_mentry: new_res.entry,
        )
      end

      def publish_rename(container, call, envelope)
        container.steps.publish(
          :entry_renamed,
          ctx: Textus::Step::Context.for(container: container, call: call),
          key: @new_key,
          from_key: @old_key,
          to_key: @new_key,
          envelope: envelope,
        )
      end

      def success_result(old_res, new_res, envelope)
        {
          "protocol" => PROTOCOL,
          "ok" => true,
          "from_key" => @old_key,
          "to_key" => @new_key,
          "from_path" => old_res.path,
          "to_path" => new_res.path,
          "uid" => envelope.uid,
          "envelope" => envelope.to_h_for_wire,
        }
      end

      def prepare(container, call)
        Textus::Manifest::Data.validate_key!(@old_key)
        Textus::Manifest::Data.validate_key!(@new_key)
        raise UsageError.new("mv: old and new keys are identical") if @old_key == @new_key

        old_res = container.manifest.resolver.resolve(@old_key)
        new_res = container.manifest.resolver.resolve(@new_key)
        raise UnknownKey.new(@old_key) unless reader(container).exists?(@old_key)

        validate_zone_and_format!(old_res.entry, new_res.entry)
        auth(container).check_action!(action: :key_mv, actor: call.role, key: @old_key)
        auth(container).check_action!(action: :key_mv, actor: call.role, key: @new_key)
        raise UsageError.new("mv: target '#{@new_key}' already exists at #{new_res.path}") if reader(container).exists?(@new_key)

        [old_res, new_res]
      end

      def validate_zone_and_format!(old_mentry, new_mentry)
        if old_mentry.lane != new_mentry.lane
          raise UsageError.new(
            "mv: cross-zone move refused (#{old_mentry.lane} -> #{new_mentry.lane}). " \
            "Use put+delete for cross-zone moves.",
          )
        end
        return if old_mentry.format == new_mentry.format

        raise UsageError.new("mv: format mismatch (#{old_mentry.format} -> #{new_mentry.format}); refusing.")
      end

      def ensure_uid!(container, call, old_mentry)
        pre_env = reader(container).read(@old_key)
        return if pre_env.uid

        writer(container, call).put(
          @old_key,
          mentry: old_mentry,
          payload: Textus::Envelope::IO::Writer::Payload.new(
            meta: pre_env.meta,
            body: pre_env.body,
            content: pre_env.content,
          ),
        )
      end

      def dry_run_result(container, old_res, new_res)
        pre_env = reader(container).read(@old_key)
        {
          "protocol" => PROTOCOL,
          "ok" => true,
          "dry_run" => true,
          "from_key" => @old_key,
          "to_key" => @new_key,
          "from_path" => old_res.path,
          "to_path" => new_res.path,
          "uid" => pre_env.uid,
        }
      end

      def auth(container)
        Textus::Gate::Auth.new(container)
      end

      def writer(container, call)
        Textus::Envelope::IO::Writer.from(container: container, call: call)
      end

      def reader(container)
        Textus::Envelope::IO::Reader.from(container: container)
      end
    end
  end
end
