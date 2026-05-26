require "fileutils"

module Textus
  module Application
    module Writes
      class Mv
        MovePlan = Data.define(
          :old_key, :new_key, :old_path, :new_path,
          :new_mentry, :uid, :etag_before
        )

        def initialize(ctx:, bus:)
          @ctx = ctx
          @bus = bus
        end

        def call(old_key, new_key, dry_run: false)
          plan, pre_env = prepare_plan(old_key, new_key)
          return dry_run_result(plan) if dry_run

          plan = ensure_uid!(plan, pre_env: pre_env)
          etag_after = perform_move!(plan)
          new_envelope = record_move(plan, etag_after: etag_after)
          success_result(plan, new_envelope: new_envelope)
        end

        private

        def manifest = @ctx.store.manifest
        def reader   = @ctx.store.reader

        def prepare_plan(old_key, new_key)
          manifest.validate_key!(old_key)
          manifest.validate_key!(new_key)
          raise UsageError.new("mv: old and new keys are identical") if old_key == new_key

          old_mentry, old_path, = manifest.resolve(old_key)
          raise UnknownKey.new(old_key) unless File.exist?(old_path)

          new_mentry, new_path, = manifest.resolve(new_key)
          validate_zone_and_format!(old_mentry, new_mentry)
          validate_writer!(old_mentry, old_key)
          raise UsageError.new("mv: target '#{new_key}' already exists at #{new_path}") if File.exist?(new_path)

          pre_env = reader.get(old_key)
          plan = MovePlan.new(
            old_key: old_key, new_key: new_key,
            old_path: old_path, new_path: new_path,
            new_mentry: new_mentry,
            uid: pre_env.uid, etag_before: pre_env.etag
          )
          [plan, pre_env]
        end

        def validate_zone_and_format!(old_mentry, new_mentry)
          if old_mentry.zone != new_mentry.zone
            raise UsageError.new(
              "mv: cross-zone move refused (#{old_mentry.zone} → #{new_mentry.zone}). " \
              "Use put+delete for cross-zone moves.",
            )
          end
          return if old_mentry.format == new_mentry.format

          raise UsageError.new("mv: format mismatch (#{old_mentry.format} → #{new_mentry.format}); refusing.")
        end

        def validate_writer!(mentry, key)
          writers = manifest.zone_writers(mentry.zone)
          return if writers.include?(@ctx.role)

          raise WriteForbidden.new(key, mentry.zone, writers: writers)
        end

        def ensure_uid!(plan, pre_env:)
          return plan if plan.uid

          env = Textus::Application::Writes::Put.new(ctx: @ctx, bus: @bus).call(
            plan.old_key,
            meta: pre_env.meta,
            body: pre_env.body,
            content: pre_env.content,
            suppress_events: true,
          )
          plan.with(uid: env.uid, etag_before: env.etag)
        end

        def perform_move!(plan)
          FileUtils.mkdir_p(File.dirname(plan.new_path))
          FileUtils.mv(plan.old_path, plan.new_path)
          rewrite_name_for_mv!(plan.new_mentry, plan.new_path, plan.new_key)
          Etag.for_file(plan.new_path)
        end

        def record_move(plan, etag_after:)
          extras = {
            "from_key" => plan.old_key, "to_key" => plan.new_key,
            "from_path" => plan.old_path, "to_path" => plan.new_path,
            "uid" => plan.uid
          }
          extras["correlation_id"] = @ctx.correlation_id if @ctx.correlation_id

          @ctx.store.audit_log.append(
            role: @ctx.role, verb: "mv", key: plan.new_key,
            etag_before: plan.etag_before, etag_after: etag_after,
            extras: extras
          )
          new_envelope = reader.get(plan.new_key)
          @bus.publish(:entry_renamed,
                       store: @ctx.with_role(@ctx.role),
                       key: plan.new_key,
                       from_key: plan.old_key,
                       to_key: plan.new_key,
                       envelope: new_envelope,
                       correlation_id: @ctx.correlation_id)
          new_envelope
        end

        def dry_run_result(plan)
          {
            "protocol" => PROTOCOL, "ok" => true, "dry_run" => true,
            "from_key" => plan.old_key, "to_key" => plan.new_key,
            "from_path" => plan.old_path, "to_path" => plan.new_path,
            "uid" => plan.uid
          }
        end

        def success_result(plan, new_envelope:)
          {
            "protocol" => PROTOCOL, "ok" => true,
            "from_key" => plan.old_key, "to_key" => plan.new_key,
            "from_path" => plan.old_path, "to_path" => plan.new_path,
            "uid" => plan.uid,
            "envelope" => new_envelope.to_h_for_wire
          }
        end

        def rewrite_name_for_mv!(mentry, new_path, new_key)
          basename = new_key.split(".").last
          Entry.for_format(mentry.format).rewrite_name(new_path, basename)
        end
      end
    end
  end
end
