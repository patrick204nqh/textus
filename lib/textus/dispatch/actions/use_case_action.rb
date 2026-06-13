# frozen_string_literal: true

module Textus
  module Dispatch
    module Actions
      # Adapter: wraps an existing use-case class as an Action.
      # This lets gate routing delegate to established use cases.
      class UseCaseAction < Base
        BURN = :sync

        def initialize(use_case_class, bound_args:, bound_kwargs:)
          super()
          @use_case_class = use_case_class
          @bound_args = bound_args
          @bound_kwargs = bound_kwargs
        end

        def call(container:, call:)
          @use_case_class.new(container: container, call: call)
                         .call(*@bound_args, **@bound_kwargs)
        end

        def args = {}
      end
    end
  end
end
