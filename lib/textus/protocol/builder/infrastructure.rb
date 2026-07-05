module Textus
  module Protocol
    class Builder
      class Infrastructure
        Components = Data.define(:database, :file_system, :store, :layout)

        def call(root)
          layout = Layout.new(root)
          database = Infra::Database.new(layout:).setup!
          file_system = Infra::FileSystem.new
          store = Infra::Store.new(database:, file_system:)
          Components.new(database:, file_system:, store:, layout:)
        end
      end
    end
  end
end
