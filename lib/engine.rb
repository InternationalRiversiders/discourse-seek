# frozen_string_literal: true
module ::DiscourseSeek
  class Engine < ::Rails::Engine
    engine_name "discourse-seek"
    isolate_namespace ::DiscourseSeek
    config.root = File.expand_path("..", __dir__)
  end
end
