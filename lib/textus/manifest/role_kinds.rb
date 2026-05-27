module Textus
  class Manifest
    module RoleKinds
      DEFAULT_MAPPING = {
        "human" => :accept_authority,
        "agent" => :proposer,
        "builder" => :generator,
        "runner" => :runner,
      }.freeze

      # Returns { role_name => kind_symbol }. When `roles:` is declared we use
      # exactly that; defaults are *not* layered in (declaring roles is an opt-in
      # to a fully user-defined vocabulary).
      def self.resolve(raw_roles)
        return DEFAULT_MAPPING if raw_roles.nil?

        raw_roles.to_h { |r| [r["name"], r["kind"].to_sym] }.freeze
      end
    end
  end
end
