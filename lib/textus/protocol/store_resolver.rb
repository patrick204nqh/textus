module Textus
  module Protocol
    module StoreResolver
      STORE_DIR = ".textus"

      module_function

      def resolve(env: ENV, cwd: Dir.pwd)
        root = env["TEXTUS_ROOT"]
        return File.expand_path(root) if root && !root.empty?

        candidate = cwd
        loop do
          store_path = File.join(candidate, STORE_DIR)
          return File.expand_path(candidate) if File.directory?(store_path)

          parent = File.dirname(candidate)
          break if parent == candidate

          candidate = parent
        end

        raise Textus::IoError.new("no .textus store found from #{cwd}")
      end
    end
  end
end
