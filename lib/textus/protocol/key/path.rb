module Textus
  module Protocol
    module Key
      module Path
        def self.resolve(data, mentry)
          primary_ext = Textus::Protocol::Format.for(mentry.format).extensions.first
          rel_path = normalize_relative_path(mentry.path)
          if File.extname(mentry.path) == ""
            File.join(data.root, rel_path + primary_ext)
          else
            File.join(data.root, rel_path)
          end
        end

        def self.normalize_relative_path(path)
          return path if path.start_with?("data/")

          File.join("data", path)
        end
      end
    end
  end
end
