# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      class BootStore < Base
        handles Dispatch::Contracts::BootStore
        needs :manifest, :file_system, :schemas, :audit_log, :layout, :pipeline

        def call
          storage    = Store::Container::Storage.new(file_system:, entry_store: nil, layout:, entry_index: nil)
          events     = Store::Container::Events.new(event_store: nil, workflows: nil)
          governance = Store::Container::Governance.new(manifest:, schemas:)
          logging    = Store::Container::Logging.new(audit_log:)
          links      = Store::Container::Links.new(link_graph: nil)
          proxy = Store::Container.new(
            storage:, events:, governance:, logging:, links:,
            root: layout.root, pipeline:
          )
          success(Textus::Protocol::Boot.build(container: proxy))
        end
      end
    end
  end
end
