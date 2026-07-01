module Textus
  module DependencyAdapters
    class SqliteAdapter
      def open(path)
        SQLite3::Database.new(path)
      end
    end
  end
end
