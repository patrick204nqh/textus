module Textus
  module Jobs
    class Planner
      ACTIONS_BY_TRIGGER = {
        "manual.kick" => %w[materialize refresh_data sweep],
        "schedule.tick" => %w[materialize refresh_data sweep],
        "entry.written" => %w[materialize decorate],
        "entry.deleted" => %w[materialize],
        "entry.moved" => %w[materialize],
        "proposal.accepted" => %w[materialize decorate],
        "proposal.rejected" => %w[materialize],
      }.freeze

      def initialize(container:)
        @container = container
        @manifest = container.manifest
      end

      def plan(triggers:, scope:, role:)
        types = Array(triggers).map { |t| t["type"] || t[:type] }.compact
        return [] if types.empty?

        prefix = scope_prefix(scope)
        zone = scope_zone(scope)
        jobs = []
        actions = coalesced_actions(types)

        if actions.include?("materialize")
          producible_keys(prefix, zone).each do |key|
            jobs << job("materialize", { "key" => key }, Textus::Role::AUTOMATION)
          end
        end

        if actions.include?("refresh_data")
          stale_intake_keys(prefix, zone).each do |key|
            jobs << job("refresh_data", { "key" => key }, Textus::Role::AUTOMATION)
          end
        end

        jobs << job("sweep", { "scope" => { "prefix" => prefix, "zone" => zone } }, role) if actions.include?("sweep")

        if actions.include?("decorate")
          producible_keys(prefix, zone).each do |key|
            jobs << job("decorate", { "key" => key }, Textus::Role::AUTOMATION)
          end
        end

        jobs
      end

      private

      def job(type, args, enqueued_by)
        Textus::Domain::Jobs::Job.new(type: type, args: args, enqueued_by: enqueued_by)
      end

      def producible_keys(prefix, zone)
        @manifest.data.entries
                 .select { |e| e.derived? || !e.publish_tree.nil? || !e.publish_to.empty? }
                 .select { |e| in_scope?(e, prefix, zone) }
                 .map(&:key)
      end

      def stale_intake_keys(prefix, zone)
        Textus::Domain::Freshness::Evaluator.new(
          manifest: @manifest,
          file_stat: Textus::Ports::Storage::FileStat.new,
          clock: Textus::Ports::Clock.new,
        ).stale_intake_keys(prefix: prefix, zone: zone)
      end

      def in_scope?(entry, prefix, zone)
        return false if zone && entry.zone != zone
        return false if prefix && !entry.key.start_with?(prefix)

        true
      end

      def scope_prefix(scope)
        scope.is_a?(Hash) ? (scope["prefix"] || scope[:prefix]) : nil
      end

      def scope_zone(scope)
        scope.is_a?(Hash) ? (scope["zone"] || scope[:zone]) : nil
      end

      def coalesced_actions(types)
        types.flat_map { |type| ACTIONS_BY_TRIGGER.fetch(type, []) }.uniq
      end
    end
  end
end
