# name: discourse-slackdoor
# about: Slackdoor plugin for Discourse
# version: 0.1
# authors: Dave McClure (mcwumbly)
# url: https://github.com/mcwumbly/discourse-slackdoor

enabled_site_setting :discourse_slackdoor_enabled

PLUGIN_NAME = "discourse-slackdoor".freeze

after_initialize do

  module ::DiscourseSlackdoor
    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscourseSlackdoor
    end
  end

  require_dependency "application_controller"
  class DiscourseSlackdoor::SlackdoorController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_filter :slackdoor_enabled?
    before_filter :slackdoor_username_present?
    before_filter :slackdoor_token_valid?

    def knock
      route = topic_route params[:text]
      post_number = route[:post_number] ? route[:post_number].to_i : 1

      topic = find_topic(route[:topic_id], post_number)
      post = find_post(topic, post_number)

      render json: slack_message(topic, post)
    end

    def slackdoor_enabled?
      raise Discourse::NotFound unless SiteSetting.discourse_slackdoor_enabled
    end

    def slackdoor_token_valid?
      raise Discourse::InvalidAccess.new unless SiteSetting.discourse_slackdoor_token
      raise Discourse::InvalidAccess.new unless SiteSetting.discourse_slackdoor_token == params[:token]
    end

    def slackdoor_username_present?
      raise Discourse::InvalidAccess.new unless SiteSetting.discourse_slackdoor_username
    end

    def topic_route(text)
      url = text.slice(text.index("<") + 1, text.index(">") -1)
      url.sub! Discourse.base_url, ''
      route = Rails.application.routes.recognize_path(url)
      raise Discourse::NotFound unless route[:controller] == 'topics' && route[:topic_id]
      route
    end

    def find_post(topic, post_number)
      topic.filtered_posts.select { |p| p.post_number == post_number}.first
    end

    def find_topic(topic_id, post_number)
      user = User.find_by_username SiteSetting.discourse_slackdoor_username
      TopicView.new(topic_id, user, {post_number: post_number})
    end

    def slack_message(topic, post)
      display_name = post.user.name
      pretext = post.try(:is_first_post?) ? "topic by #{display_name}" : "reply by #{display_name}"
      response = {
        attachments: [
          {
            fallback: "#{topic.title} - #{pretext}",
            author_name: display_name,
            color: '#' + ColorScheme.hex_for_name('header_background'),
            pretext: pretext,
            title: topic.title,
            title_link: post.full_url,
            text: post.excerpt(400, text_entities: true, strip_links: true)
          }
        ]
      }
    end

    # Override ApplicationController access control methods
    def handle_unverified_request
    end

    def is_api?
      true
    end

    def redirect_to_login_if_required
    end

  end

  DiscourseSlackdoor::Engine.routes.draw do
    post "/knock" => "slackdoor#knock"
  end

  Discourse::Application.routes.prepend do
    mount ::DiscourseSlackdoor::Engine, at: "/slackdoor"
  end


end
