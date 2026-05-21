module Textus
  module Doctor
    class Check
      class ManifestFiles < Check
        def call
          out = []
          store.manifest.entries.each do |entry|
            next if entry.nested

            path = leaf_path_for(entry)
            next if File.exist?(path)

            out << {
              "code" => "manifest.missing_file",
              "level" => "info",
              "subject" => entry.key,
              "message" => "declared entry has no file on disk at #{path}",
              "fix" => "create the entry with 'textus put #{entry.key} --stdin --as=<role>' " \
                       "(or leave empty if not yet authored)",
            }
          end
          out
        end

        private

        def leaf_path_for(entry)
          primary_ext = Entry.for_format(entry.format).extensions.first
          if File.extname(entry.path) == ""
            File.join(store.root, "zones", entry.path + primary_ext)
          else
            File.join(store.root, "zones", entry.path)
          end
        end
      end
    end
  end
end
