# frozen_string_literal: true

module Textus
  module Dispatch
    module Planner
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

        SCOPE_RESOLVERS = {
          "materialize" => :producible_keys,
          "refresh_data" => :stale_intake_keys,
          "sweep" => :lane_keys,
          "decorate" => :producible_keys,
        }.freeze

        def initialize(container:)
          @container = container
          @manifest  = container.manifest
        end

        def plan(trigger:, role:)
          type = trigger["type"] || trigger[:type]
          trigger["target"] || trigger[:target]
          return [] if type.nil?

          blocks_with_react = @manifest.rules.blocks.select(&:react)
          if blocks_with_react.any?
            plan_from_rules(blocks_with_react, type, role)
          else
            plan_from_defaults(type, role)
          end
        end

        private

        def plan_from_rules(blocks, type, role)
          jobs = []
          blocks
            .select { |b| matches_trigger?(b.react, type) }
            .each do |block|
              do_action = block.react.raw["do"]
              Array(do_action).each do |action|
                if action == "sweep"
                  jobs << Textus::Core::Jobs::Job.new(
                    type: "sweep", args: { "scope" => {} }, enqueued_by: role,
                  )
                else
                  resolver = SCOPE_RESOLVERS.fetch(action, :producible_keys)
                  keys = send(resolver, nil)
                  keys.each { |key| jobs << job(action, key, role) }
                end
              end
            end
          jobs
        end

        def plan_from_defaults(type, role)
          actions = ACTIONS_BY_TRIGGER.fetch(type, [])
          jobs = []
          producible_keys(nil).each { |k| jobs << job("materialize", k, role) } if actions.include?("materialize")
          stale_intake_keys(nil).each { |k| jobs << job("refresh_data", k, role) } if actions.include?("refresh_data")
          if actions.include?("sweep")
            jobs << Textus::Core::Jobs::Job.new(
              type: "sweep", args: { "scope" => {} }, enqueued_by: role,
            )
          end
          jobs
        end

        def matches_trigger?(react, type)
          on = react.raw["on"]
          Array(on).include?(type)
        end

        def job(type, key, enqueued_by)
          Textus::Core::Jobs::Job.new(type: type, args: { "key" => key }, enqueued_by: enqueued_by)
        end

        def producible_keys(_target)
          @manifest.data.entries
                   .select { |e| e.derived? || !e.publish_tree.nil? || !e.publish_to.empty? }
                   .map(&:key)
        end

        def stale_intake_keys(_target)
          Textus::Core::Freshness::Evaluator.new(
            manifest: @manifest,
            file_stat: Textus::Ports::Storage::FileStat.new,
            clock: Textus::Ports::Clock.new,
          ).stale_intake_keys(prefix: nil, lane: nil)
        end

        def lane_keys(_target)
          @manifest.data.entries.map(&:key)
        end
      end
    end
  end
end
