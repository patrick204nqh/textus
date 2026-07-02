# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      class BootStore < Base
        handles Dispatch::Contracts::BootStore
        needs :manifest, :file_system, :schemas, :audit_log, :layout, :pipeline

        def call
          proxy = Store::Infrastructure.build(
            manifest:, file_system:,
            schemas:, audit_log:,
            layout:, root: layout.root,
            pipeline:
          )
          success(Textus::Boot.build(container: proxy))
        end
      end
    end
  end
end
