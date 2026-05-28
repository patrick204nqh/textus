module Textus
  module Doctor
    class Check
      class IllegalKeys < Check
        def call
          out = []
          store.manifest.data.entries.each do |entry|
            next unless entry.nested?

            base = File.join(store.root, "zones", entry.path)
            next unless File.directory?(base)

            index_fn = entry.respond_to?(:index_filename) ? entry.index_filename : nil
            index_fn ? check_index_paths(entry, index_fn, base, out) : check_all_paths(base, out)
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
        def check_index_paths(_entry, index_fn, base, out)
          Dir.glob(File.join(base, "**", index_fn)).each do |fp|
            rel = fp.sub(%r{\A#{Regexp.escape(base)}/?}, "")
            File.dirname(rel).split("/").reject { |s| s.empty? || s == "." }.each do |seg|
              next if seg.match?(Key::Grammar::SEGMENT)

              out << issue(fp, seg)
            end
          end
        end

        def issue(abs_path, stem)
          {
            "code" => "key.illegal",
            "level" => "error",
            "subject" => abs_path,
            "path" => abs_path,
            "message" => "illegal key segment '#{stem}' at #{abs_path}",
            "fix" => "rename the file/directory so each segment matches [a-z0-9][a-z0-9-]* " \
                     "(lowercase, digits, hyphens)",
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
