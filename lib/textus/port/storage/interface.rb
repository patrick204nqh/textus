module Textus
  module Port
    module Storage
      module Interface
        def read(path) = raise NotImplementedError
        def write(path, bytes) = raise NotImplementedError
        def delete(path) = raise NotImplementedError
        def exists?(path) = raise NotImplementedError
        def etag(path) = raise NotImplementedError
        def mkdir_p(path) = raise NotImplementedError
        def mv(from_path, to_path) = raise NotImplementedError
        def rmdir(path) = raise NotImplementedError
        def dir_empty?(dir) = raise NotImplementedError
      end
    end
  end
end
