module Textus
  module Infra
    class Store
      class FileStore
        def initialize(file_system)
          @fs = file_system
        end

        def read(path)  = @fs.read(path)

        def write(path, bytes)
          @fs.mkdir_p(File.dirname(path))
          @fs.write(path, bytes)
        end

        def delete(path)   = @fs.delete(path)
        def move(from, to) = @fs.mv(from, to)
        def exists?(path)  = @fs.exists?(path)
        def etag(path)     = Textus::Value::Etag.for_file(path)
      end
    end
  end
end
