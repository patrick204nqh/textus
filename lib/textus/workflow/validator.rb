module Textus
  module Workflow
    class Validator
      def initialize(definition, container:)
        @definition = definition
        @container  = container
      end

      def validate_all
        keys = if @definition.multi_match?
                 all_matching_keys
               else
                 @container.manifest.data.entries.select do |e|
                   @definition.match?(e.key)
                 end.map(&:key)
               end
        all_issues = []
        keys.each do |key|
          ctx = build_context(key)
          each_validate_step(ctx).each { |issue| all_issues << issue.merge("key" => key) }
        end
        {
          "workflow" => @definition.name,
          "total" => keys.size,
          "passed" => keys.size - all_issues.group_by { |i| i["key"] }.size,
          "issues" => all_issues,
        }
      end

      private

      def build_context(key)
        res = @container.manifest.resolver.resolve(key)
        Context.new(
          key: key,
          entry: res.entry,
          config: {}.freeze,
          lane: res.entry.lane.to_s,
          container: @container,
          call: nil,
        )
      end

      def all_matching_keys
        prefix = @definition.match_pattern.sub(/\.\*\*$/, "")
        rows = @container.manifest.resolver.enumerate
        rows.select { |r| r[:key].start_with?(prefix) }.map { |r| r[:key] }
      end

      def each_validate_step(ctx)
        @definition.validate_steps.flat_map { |step| step.callable.call(nil, ctx) }
      end
    end
  end
end
