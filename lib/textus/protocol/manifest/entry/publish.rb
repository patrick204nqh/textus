module Textus
  module Protocol
    class Manifest
      class Entry
        module Publish
          def self.resolve(entry)
            set = []
            set << "publish.to"   unless Array(entry.publish_to).empty?
            set << "publish.tree" unless entry.publish_tree.nil?

            if set.length > 1
              raise Textus::UsageError.new(
                "entry '#{entry.key}': #{set.join(" and ")} are mutually exclusive — an entry publishes exactly one way",
              )
            end

            mode_for(entry, set.first)
          end

          def self.mode_for(entry, key)
            case key
            when "publish.to"   then ToPaths.new(entry)
            when "publish.tree" then Tree.new(entry)
            else None.new(entry)
            end
          end
          private_class_method :mode_for

          class Mode
            def initialize(entry)
              @entry = entry
            end

            attr_reader :entry

            def validate!; end

            def keyless? = false

            private

            def repo_abs(pctx, rel)
              File.expand_path(File.join(pctx.repo_root, rel))
            end

            def inside_repo?(pctx, abs)
              abs.start_with?(File.expand_path(pctx.repo_root) + File::SEPARATOR)
            end

            def store_base(pctx)
              File.join(pctx.root, Textus::Protocol::Key::Path.normalize_relative_path(entry.path))
            end
          end

          class None < Mode
            def publish(_pctx, prefix: nil) = nil
          end
        end
      end
    end
  end
end
