# frozen_string_literal: true

module Textus
  module Step
    class Base
      class << self
        # The step kind is derived from class hierarchy.
        def kind
          return :fetch if defined?(Step::Fetch) && self <= Step::Fetch
          return :transform if defined?(Step::Transform) && self <= Step::Transform
          return :validate if defined?(Step::Validate) && self <= Step::Validate
          return :observe if defined?(Step::Observe) && self <= Step::Observe

          raise NotImplementedError.new("#{self} is not a known step kind")
        end

        # Required #call kwargs the loader validates against the subclass.
        def required_kwargs = []

        # Built-ins (and only built-ins) override the registered name when the
        # Ruby class name can't carry it (e.g. "markdown-links").
        def step_name(value = :__read__)
          if value == :__read__
            @step_name
          else
            @step_name = value.to_s
          end
        end
      end

      # Assigned by the loader/registry at registration time.
      attr_accessor :name
    end
  end
end
