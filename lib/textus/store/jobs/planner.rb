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
          @workflows = container.workflows
        end

        def plan(trigger:, role:)
          type   = trigger["type"] || trigger[:type]
          target = trigger["target"] || trigger[:target]
          return [] if type.nil?

          Textus::Manifest::TriggerCatalog.validate_trigger!(type)

          plan_from_defaults(type, role, target: target)
        end

        private

        def plan_from_defaults(type, role, target: nil)
          actions = ACTIONS_BY_TRIGGER.fetch(type, [])
          jobs = []
          if actions.include?("materialize")
            keys = target && ENTRY_LEVEL_TRIGGERS.include?(type) ? dependent_keys(target) : producible_keys
            sort_by_priority(keys).each { |k| jobs << job("materialize", k, role) }
          end
          GLOBAL_ACTIONS.each do |action, args|
            jobs << Textus::Store::Jobs::Queue::Job.new(type: action, args: args, role: role) if actions.include?(action)
          end
          jobs
        end

        def job(type, key, role)
          Textus::Store::Jobs::Queue::Job.new(type: type, args: { "key" => key }, role: role)
        end

        def producible_keys
          @workflows.map(&:match_pattern).compact
        end

        def dependent_keys(target_key)
          @workflows
            .select { |w| w.depends_on_patterns.any? { |p| match_depends?(p, target_key) } }
            .map(&:match_pattern)
            .compact
        end

        def match_depends?(pattern, target_key)
          target_key == pattern || target_key.start_with?("#{pattern}.")
        end

        def sort_by_priority(keys)
          keys.sort_by { |k| -priority_for(k) }
        end

        def priority_for(key)
          wf = @workflows.find { |d| d.match?(key) }
          wf&.priority || 0
        end
      end
    end
  end
end
