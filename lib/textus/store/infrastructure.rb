# frozen_string_literal: true

module Textus
  class Store
    Infrastructure = Data.define(
      :manifest,
      :file_system,
      :schemas,
      :audit_log,
      :database,
      :event_store,
      :layout,
      :link_edge_store,
      :workflows,
      :root,
      :reader,
      :writer,
      :ttl_evaluator,
      :trace_buffer,
      :pipeline,
    ) do
      def self.build(**kwargs)
        members = self.members
        defaults = members - kwargs.keys
        new(**kwargs, **defaults.to_h { |m| [m, nil] })
      end
    end
  end
end
