# frozen_string_literal: true

module Textus
  class Store
    module Jobs
      class Planner
        ACTIONS_BY_TRIGGER = {
          "convergence" => %w[materialize sweep index],
          "entry.written" => %w[materialize],
          "entry.deleted" => %w[materialize],
          "entry.moved" => %w[materialize],
          "proposal.accepted" => %w[materialize],
          "proposal.rejected" => %w[materialize],
        }.freeze

        ENTRY_LEVEL_TRIGGERS = %w[
          entry.written entry.deleted entry.moved
          proposal.accepted proposal.rejected
        ].freeze

        SCOPE_RESOLVERS = {
          "materialize" => :producible_keys,
          "sweep" => :lane_keys,
        }.freeze

        GLOBAL_ACTIONS = {
          "index" => {},
          "sweep" => { "scope" => {} },
        }.freeze

        def self.seed(container:, queue:, role:)
          jobs = new(container: container).plan(
            trigger: { "type" => "convergence" },
            role: role,
          )
          jobs.each { |j| queue.enqueue(j) }
        end

        def initialize(container:)
          @container = container
          @manifest  = container.manifest
        end

        def plan(trigger:, role:)
          type   = trigger["type"] || trigger[:type]
          target = trigger["target"] || trigger[:target]
          return [] if type.nil?

          blocks_with_react = @manifest.rules.blocks.select(&:react)
          if blocks_with_react.any?
            plan_from_rules(blocks_with_react, type, role, target: target)
          else
            plan_from_defaults(type, role, target: target)
          end
        end

        private

        def plan_from_rules(blocks, type, role, target: nil) # rubocop:disable Lint/UnusedMethodArgument
          jobs = []
          blocks
            .select { |b| matches_trigger?(b.react, type) }
            .each do |block|
              do_action = block.react.raw["do"]
              Array(do_action).each do |action|
                if (global_args = GLOBAL_ACTIONS[action])
                  jobs << Textus::Store::Jobs::Queue::Job.new(type: action, args: global_args, role: role)
                else
                  resolver = SCOPE_RESOLVERS.fetch(action, :producible_keys)
                  keys = send(resolver, nil)
                  keys.each { |key| jobs << job(action, key, role) }
                end
              end
            end
          jobs
        end

        def plan_from_defaults(type, role, target: nil)
          actions = ACTIONS_BY_TRIGGER.fetch(type, [])
          jobs = []
          if actions.include?("materialize")
            keys = target && ENTRY_LEVEL_TRIGGERS.include?(type) ? dependent_keys(target) : producible_keys(nil)
            keys.each { |k| jobs << job("materialize", k, role) }
          end
          GLOBAL_ACTIONS.each do |action, args|
            jobs << Textus::Store::Jobs::Queue::Job.new(type: action, args: args, role: role) if actions.include?(action)
          end
          jobs
        end

        def matches_trigger?(react, type)
          on = react.raw["on"]
          Array(on).include?(type)
        end

        def job(type, key, role)
          Textus::Store::Jobs::Queue::Job.new(type: type, args: { "key" => key }, role: role)
        end

        def producible_keys(_target)
          @manifest.data.entries
                   .select { |e| !e.publish_tree.nil? || !e.publish_to.empty? }
                   .map(&:key)
        end

        def lane_keys(_target)
          @manifest.data.entries.map(&:key)
        end

        def dependent_keys(target_key)
          @manifest.data.entries
                   .select(&:external?)
                   .select do |e|
                     Array(e.source&.sources).compact.any? do |s|
                       target_key == s || target_key.start_with?("#{s}.")
                     end
                   end
                   .select { |e| !e.publish_tree.nil? || !e.publish_to.empty? }
                   .map(&:key)
        end
      end
    end
  end
end
