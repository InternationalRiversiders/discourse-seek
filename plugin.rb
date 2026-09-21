# frozen_string_literal: true
# name: discourse-seek
# about: 觅电 — Riverside native community application
# version: 0.2.0
# authors: Riverside
# url: https://github.com/InternationalRiversiders/discourse-seek
# required_version: 2026.9.0-latest

enabled_site_setting :food_enabled
register_asset "stylesheets/food.scss"
%w[utensils heart star magnifying-glass location-dot rotate plus comment image circle-check pen-to-square trash-can flag link download chevron-right chevron-left].each { |icon| register_svg_icon icon }
require_relative "lib/engine"
after_initialize do
  require_relative "lib/core"
  require_relative "lib/business"
  require_relative "lib/importer"
  require_relative "lib/user_lifecycle"
  add_to_serializer(:current_user, :food_member) { SiteSetting.food_enabled && DiscourseSeek::Access.member?(object) }

  Discourse::Application.routes.append { mount DiscourseSeek::Engine, at: "/food" }
end
