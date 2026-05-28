module Textus
  module Doctor
    class Check
      class ManifestFiles < Check
        def call
          store.manifest.data.entries.each_with_object([]) do |entry, out|
            next if entry.nested?

            path = Textus::Key::Path.resolve(store.manifest.data, entry)
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
        end
      end
    end
  end
end
