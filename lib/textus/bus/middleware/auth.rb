require "set"

module Textus
  module Bus
    module Middleware
      class Auth < Base
        middleware_name :auth

        def initialize(manifest)
          @manifest = manifest
          @schemas = nil
        end

        def call(command, call, next_handler)
          verb = verb_for(command.class)
          floor_preds = Textus::Gate::Auth::FLOOR.fetch(verb, [])
          rule_preds = rule_declared_predicates(verb, key_for(command))

          (floor_preds + rule_preds).uniq.each do |pred_name|
            evaluate(pred_name, verb, command, call)
          end

          next_handler.call(command)
        end

        private

        CONTRACT_TO_VERB = {
          Contracts::GetEntry => :get,
          Contracts::PutEntry => :put,
          Contracts::ListKeys => :list,
          Contracts::DeleteKey => :key_delete,
          Contracts::MoveKey => :key_mv,
          Contracts::ProposeEntry => :propose,
          Contracts::AcceptProposal => :accept,
          Contracts::RejectProposal => :reject,
          Contracts::EnqueueJob => :enqueue,
          Contracts::AuditEntries => :audit,
          Contracts::PulseEntries => :pulse,
          Contracts::BlameEntry => :blame,
          Contracts::WhereEntry => :where,
          Contracts::UidEntry => :uid,
          Contracts::DepsEntry => :deps,
          Contracts::RdepsEntry => :rdeps,
          Contracts::BootStore => :boot,
          Contracts::DoctorStore => :doctor,
          Contracts::PublishedEntries => :published,
          Contracts::RuleExplain => :rule_explain,
          Contracts::RuleList => :rule_list,
          Contracts::SchemaEnvelope => :schema_show,
          Contracts::DrainStore => :drain,
          Contracts::IngestEntry => :ingest,
          Contracts::JobsAction => :jobs,
          Contracts::RuleLint => :rule_lint,
          Contracts::DataMv => :data_mv,
          Contracts::KeyMvPrefix => :key_mv_prefix,
          Contracts::KeyDeletePrefix => :key_delete_prefix,
        }.freeze

        def verb_for(klass)
          CONTRACT_TO_VERB[klass] or raise("unknown contract class: #{klass}")
        end

        def key_for(command)
          if command.respond_to?(:key) then command.key
          elsif command.respond_to?(:old_key) then command.old_key
          elsif command.respond_to?(:pending_key) then command.pending_key
          else nil
          end
        end

        def rule_declared_predicates(verb, key)
          return [] unless key

          guard_map = @manifest.rules.for(key).guard
          return [] if guard_map.nil?

          Array(guard_map[verb.to_s])
        end

        def evaluate(pred_name, verb, command, call)
          case pred_name
          when "lane_writable_by"     then check_lane_writable(verb, command, call)
          when "author_held"          then check_author_held(verb, command, call)
          when "target_is_canon"      then check_target_is_canon(command)
          when "etag_match"           then nil
          when "schema_valid"         then nil
          when "fresh_within"         then nil
          when "raw_lane_ingest_only" then check_raw_ingest_only(verb, command)
          when "raw_write_once"       then check_raw_write_once(verb, command)
          when "lane_deletable_by"    then check_lane_deletable(verb, command, call)
          else raise Textus::UsageError.new("unknown predicate '#{pred_name}'")
          end
        end

        def resolve_entry(key)
          @manifest.resolver.resolve(key).entry
        rescue Textus::UnknownKey
          nil
        end

        def lane_verb(entry)
          @manifest.policy.verb_for_lane(entry.lane.to_s)
        end

        def caps(role)
          Set.new(@manifest.data.role_caps.fetch(role.to_s, []))
        end

        def check_lane_writable(verb, command, call)
          key = key_for(command) or return
          entry = resolve_entry(key) or return
          lv = lane_verb(entry) or return
          return if caps(call.role).include?(lv.to_s)

          holders = @manifest.policy.roles_with_capability(lv.to_s)
          raise Textus::WriteForbidden.new(entry.key, entry.lane, verb: lv, holders: holders)
        end

        def check_author_held(verb_name, command, call)
          holders = @manifest.policy.roles_with_capability("author")
          return if holders.include?(call.role.to_s)

          reason = if holders.empty?
                     "no role holds the 'author' capability; #{verb_name} is disabled"
                   else
                     "role '#{call.role}' lacks the 'author' capability (held by: #{holders.join(", ")})"
                   end
          raise Textus::GuardFailed.new([["author_held", reason]])
        end

        def check_target_is_canon(command)
          key = key_for(command) or return
          entry = resolve_entry(key) or return
          kind = @manifest.policy.declared_kind(entry.lane.to_s)
          return if kind == :canon

          raise Textus::ProposalError.new("target lane '#{entry.lane}' is not canon (kind: #{kind})")
        end

        def check_raw_ingest_only(verb, command)
          key = key_for(command) or return
          entry = resolve_entry(key) or return
          return unless @manifest.policy.declared_kind(entry.lane.to_s) == :raw
          return if verb == :ingest

          raise Textus::Error.new(:raw_lane_ingest_only,
            "raw lane '#{entry.lane}' only accepts `textus ingest` — use that verb instead of '#{verb}'")
        end

        def check_raw_write_once(verb_name, command)
          key = if command.is_a?(Contracts::IngestEntry)
                  derive_ingest_key(command)
                else
                  key_for(command)
                end
          return unless key

          path = @manifest.resolver.resolve(key).path
          return unless File.exist?(path)

          raise Textus::Error.new(:raw_write_once,
            "raw entry '#{key}' already exists; delete it first, then re-ingest")
        end

        def derive_ingest_key(command)
          now = Time.now.utc
          date = now.strftime("%Y.%m.%d")
          "raw.#{date}.#{command.kind}-#{command.slug}"
        end

        def check_lane_deletable(verb, command, call)
          key = key_for(command) or return
          entry = resolve_entry(key) or return
          is_raw = @manifest.policy.declared_kind(entry.lane.to_s) == :raw

          pass = if is_raw
                   caps(call.role).include?("author")
                 else
                   lv = lane_verb(entry)
                   caps(call.role).include?(lv.to_s) || caps(call.role).include?("author")
                 end
          return if pass

          lv = lane_verb(entry)
          extra_holders = is_raw ? ["author"] : [lv.to_s, "author"]
          holders = extra_holders.flat_map { |v| @manifest.policy.roles_with_capability(v) }.uniq
          raise Textus::WriteForbidden.new(entry.key, entry.lane, verb: lv, holders: holders)
        end
      end
    end
  end
end
