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

            entry.index_filename ? check_index_paths(entry, base, out) : check_all_paths(base, out)
          end
          out
        end

        private

        def check_all_paths(base, out)
          walk_nested(base) do |abs_path, is_dir|
            basename = File.basename(abs_path)
            stem = is_dir ? basename : basename.sub(/#{Regexp.escape(File.extname(basename))}\z/, "")
            next if stem.match?(Key::Grammar::SEGMENT)

            out << issue(abs_path, stem)
          end
        end

        # When the entry uses `index_filename:`, only the parent-directory
        # segments leading to each index file participate in keys. Sibling
        # files and unrelated subtrees are not enumerated and must not be
        # flagged. Each illegal segment is reported once per path.
        def check_index_paths(entry, base, out)
          Dir.glob(File.join(base, "**", entry.index_filename)).each do |fp|
            rel = fp.sub(%r{\A#{Regexp.escape(base)}/?}, "")
            File.dirname(rel).split("/").reject { |s| s.empty? || s == "." }.each do |seg|
              next if seg.match?(Key::Grammar::SEGMENT)

              out << issue(fp, seg)
            end
          end
        end

        def issue(abs_path, stem)
          proposed = Textus::MigrateKeys.normalize(stem)
          {
            "code" => "key.illegal",
            "level" => "error",
            "subject" => abs_path,
            "path" => abs_path,
            "proposed_key" => proposed,
            "message" => "illegal key segment '#{stem}' at #{abs_path}",
            "fix" => "run 'textus key normalize --dry-run' then '--write' to rename to '#{proposed}'",
          }
        end

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
