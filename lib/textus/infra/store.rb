module Textus
  module Infra
    class Store
      def initialize(database:, file_system:)
        @db = database.connection
        @file_system = file_system
      end

      attr_reader :file_system, :db

      def cursor_store   = @cursor_store   ||= CursorStore.new(@db)
      def link_store     = @link_store     ||= LinkStore.new(@db)
      def entry_index    = @entry_index    ||= EntryIndex.new(@db)
      def audit_log      = @audit_log      ||= AuditLog.new(@db)
      def workflow_queue = @workflow_queue ||= WorkflowQueue.new(@db)
      def file_store     = @file_store     ||= FileStore.new(@file_system)

      def transaction(&) = @db.transaction(&)
    end
  end
end

require_relative "store/base"
require_relative "store/cursor_store"
require_relative "store/audit_log"
require_relative "store/workflow_queue"
require_relative "store/entry_index"
require_relative "store/file_store"
require_relative "store/link_store"
