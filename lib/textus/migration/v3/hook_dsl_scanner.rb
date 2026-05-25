module Textus
  module Migration
    module V3
      module HookDSLScanner
        REWRITES = {
          # Old sugar methods (now removed entirely in Task 4.1)
          /Textus\.intake\(/ => "Textus.on(:resolve_intake, ",
          /Textus\.reduce\(/ => "Textus.on(:transform_rows, ",
          /Textus\.check\(/ => "Textus.on(:validate, ",
          /Textus\.put\(/ => "Textus.on(:entry_put, ",
          /Textus\.deleted\(/ => "Textus.on(:entry_deleted, ",
          /Textus\.refreshed\(/ => "Textus.on(:entry_refreshed, ",
          /Textus\.built\(/ => "Textus.on(:build_completed, ",
          /Textus\.accepted\(/ => "Textus.on(:proposal_accepted, ",
          /Textus\.published\(/ => "Textus.on(:file_published, ",
          /Textus\.mv\(/ => "Textus.on(:entry_renamed, ",
          /Textus\.reject\(/ => "Textus.on(:proposal_rejected, ",
          /Textus\.loaded\(/ => "Textus.on(:store_loaded, ",
          /Textus\.refresh_began\(/ => "Textus.on(:refresh_started, ",
          /Textus\.refresh_detached\(/ => "Textus.on(:refresh_backgrounded, ",
          # The generic Textus.hook form is also gone:
          /Textus\.hook\(/ => "Textus.on(",
          # Even if the user used Textus.on but with a legacy event symbol:
          /Textus\.on\(:intake\b/ => "Textus.on(:resolve_intake",
          /Textus\.on\(:reduce\b/ => "Textus.on(:transform_rows",
          /Textus\.on\(:check\b/ => "Textus.on(:validate",
          /Textus\.on\(:put\b/ => "Textus.on(:entry_put",
          /Textus\.on\(:deleted\b/ => "Textus.on(:entry_deleted",
          /Textus\.on\(:refreshed\b/ => "Textus.on(:entry_refreshed",
          /Textus\.on\(:built\b/ => "Textus.on(:build_completed",
          /Textus\.on\(:accepted\b/ => "Textus.on(:proposal_accepted",
          /Textus\.on\(:published\b/ => "Textus.on(:file_published",
          /Textus\.on\(:mv\b/ => "Textus.on(:entry_renamed",
          /Textus\.on\(:reject\b/ => "Textus.on(:proposal_rejected",
          /Textus\.on\(:loaded\b/ => "Textus.on(:store_loaded",
          /Textus\.on\(:refresh_began\b/ => "Textus.on(:refresh_started",
          /Textus\.on\(:refresh_detached\b/ => "Textus.on(:refresh_backgrounded",
        }.freeze

        def self.scan(root:)
          findings = []
          Dir.glob(File.join(root, ".textus/hooks/**/*.rb")).each do |path|
            File.foreach(path).with_index(1) do |line, lineno|
              REWRITES.each do |pattern, hint|
                next unless line.match?(pattern)

                findings << { path: path, line: lineno, original: line.chomp, hint: hint }
              end
            end
          end
          findings
        end
      end
    end
  end
end
