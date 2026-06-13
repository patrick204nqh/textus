module Textus
  module Doctor
    class Check
      class Hooks < Check
        def call
          out = []
          dir = File.join(root, "steps")
          return out unless File.directory?(dir)

          Textus::Step::Loader.new(registry: Textus::Step::RegistryStore.new).load_dir(dir)
          out
        rescue Textus::UsageError => e
          out << {
            "code" => "step.load_failed",
            "level" => "error",
            "subject" => "steps",
            "message" => e.message,
            "fix" => "open the named step file under .textus/steps/ and fix the error",
          }
          out
        end
      end
    end
  end
end
