# frozen_string_literal: true

module Textus
  # A Step is a unit of user-extensible behaviour discovered by convention at
  # .textus/steps/<kind>/<name>.rb. Five kinds: fetch (external acquisition),
  # transform (combine/reshape into an artifact), validate (check an artifact),
  # observe (react to a lifecycle event). Replaces the Textus.hook block queue.
  module Step
  end
end
