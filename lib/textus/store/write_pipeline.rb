module Textus
  class Store
    module WritePipeline
      WriteContext = Data.define(
        :key, :mentry, :payload, :if_etag,
        :path, :existing_env, :meta, :content,
        :bytes, :eff_meta, :eff_body, :eff_content,
        :etag_before, :envelope
      ) do
        def with(**attrs) = self.class.new(**to_h, **attrs)
      end

      WriteDeps = Data.define(:file_system, :manifest, :audit_log, :call, :reader, :layout, :entry_index)

      DeleteContext = Data.define(:key, :mentry, :if_etag, :path, :etag_before) do
        def with(**attrs) = self.class.new(**to_h, **attrs)
      end
      MoveContext = Data.define(:from_key, :to_key, :new_mentry, :if_etag,
                                :from_path, :to_path, :etag_before, :etag_after, :envelope) do
        def with(**attrs) = self.class.new(**to_h, **attrs)
      end

      module_function

      def put(...) = Put.call(...)
      def delete(...) = Delete.call(...)
      def move(...) = Move.call(...)
    end
  end
end

require_relative "write_pipeline/put"
require_relative "write_pipeline/delete"
require_relative "write_pipeline/move"
