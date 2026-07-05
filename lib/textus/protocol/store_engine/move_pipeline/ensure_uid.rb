module Textus
  module Protocol
    class StoreEngine
      module MovePipeline
        module EnsureUid
          def self.call(ctx, deps)
            return ctx if Infra::Store::Envelope::Meta::NO_META_FORMATS.include?(ctx.from_entry.format)
            return ctx unless ctx.from_path && deps.file_system.exists?(ctx.from_path)
            raw = deps.file_system.read(ctx.from_path)
            parsed = Format.for(ctx.from_entry.format).parse(raw, path: ctx.from_path)
            meta = parsed["_meta"] || {}
            return ctx if meta["uid"].is_a?(String) && !meta["uid"].empty?
            new_meta = Infra::Store::Envelope::Meta.inject_all(meta, parsed["content"], {},
              format: ctx.from_entry.format).first
            bytes, = Format.for(ctx.from_entry.format).serialize_for_put(
              meta: new_meta, body: parsed["body"] || "", content: parsed["content"], path: ctx.from_path)
            deps.file_system.write(ctx.from_path, bytes)
            ctx
          end
        end
      end
    end
  end
end
