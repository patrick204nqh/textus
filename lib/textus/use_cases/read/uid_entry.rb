module Textus
  module UseCases
    module Read
      class UidEntry < Base
        handles Dispatch::Contracts::UidEntry
        needs :file_system, :manifest, :layout

        def call
          reader = Store::Entry::Reader.new(file_system: @file_system, manifest: @manifest, layout: @layout)
          envelope = reader.read(@command.key)
          return failure(:not_found, "no entry at #{@command.key}") unless envelope

          success(envelope.uid)
        end
      end
    end
  end
end
