module Textus
  module Doctor
    class Check
      class IllegalKeys < Check
        def call
          out = []
          store.manifest.entries.each do |entry|
            next unless entry.nested

            base = File.join(store.root, "zones", entry.path)
            next unless File.directory?(base)

            walk_nested(base) do |abs_path, is_dir|
              basename = File.basename(abs_path)
              stem = is_dir ? basename : basename.sub(/#{Regexp.escape(File.extname(basename))}\z/, "")
              next if stem.match?(Key::Grammar::SEGMENT)

              proposed = Textus::MigrateKeys.normalize(stem)
              out << {
                "code" => "key.illegal",
                "level" => "error",
                "subject" => abs_path,
                "path" => abs_path,
                "proposed_key" => proposed,
                "message" => "illegal key segment '#{stem}' at #{abs_path}",
                "fix" => "run 'textus key migrate --dry-run' then '--write' to rename to '#{proposed}'",
              }
            end
          end
          out
        end

        private

        def walk_nested(root, &block)
          Dir.each_child(root) do |name|
            abs = File.join(root, name)
            if File.directory?(abs)
              walk_nested(abs, &block)
              yield abs, true
            else
              yield abs, false
            end
          end
        end
      end
    end
  end
end
