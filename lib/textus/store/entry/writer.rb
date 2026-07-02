require "fileutils"

module Textus
  class Store
    module Entry
      class Writer
        def initialize(file_system:, manifest:, audit_log:, reader:, layout:)
          @file_system = file_system
          @manifest   = manifest
          @audit_log  = audit_log
          @reader     = reader
          @layout     = layout
        end

        def put(key, mentry:, payload:, call:, if_etag: nil)
          WritePipeline.put(
            key, mentry:, payload:, call:, if_etag:,
            file_system: @file_system, manifest: @manifest,
            audit_log: @audit_log, reader: @reader, layout: @layout
          )
        end

        def delete(key, call:, mentry: nil, if_etag: nil)
          WritePipeline.delete(
            key, call:, mentry:, if_etag:,
            file_system: @file_system, manifest: @manifest,
            audit_log: @audit_log, reader: @reader, layout: @layout
          )
        end

        def move(from_key:, to_key:, new_mentry:, call:, if_etag: nil)
          WritePipeline.move(
            from_key:, to_key:, new_mentry:, call:, if_etag:,
            file_system: @file_system, manifest: @manifest,
            audit_log: @audit_log, reader: @reader, layout: @layout
          )
        end
      end
    end
  end
end
