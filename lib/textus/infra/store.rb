module Textus
  module Infra
    class Store
      def initialize(database:, file_system:)
        @db = database.connection
        @file_system = file_system
        @fs = file_system
      end

      attr_reader :file_system, :db

      def entry_store = EntryStore.new(@db, @fs)
      def event_store = EventStore.new(@db)
      def cursor_store = CursorStore.new(@db)
      def link_store = LinkStore.new(@db)

      def transaction(&) = @db.transaction(&)
    end
  end
end

require_relative "store/entry_store"
require_relative "store/event_store"
require_relative "store/cursor_store"
require_relative "store/link_store"
