require 'bundler'
Bundler.require

require 'active_support'
require 'active_support/core_ext'
require 'active_model'
require_relative './lib/active_model/attributes/model'
require_relative './config'
require_relative './datastore'
require_relative './github'
Dir['./services/**'].each { |f| require_relative f }

module Syncfiles
  def self.logger
    @logger ||=
      Logger.new(STDOUT).tap do |l|
        l.level = Logger::DEBUG
      end
  end
end

datastore = Datastore.new

post '/webhook' do
  params = JSON.parse(request.body.read).with_indifferent_access

  case request.env['HTTP_X_GITHUB_EVENT']&.to_sym
  when :installation
    case params[:action].to_sym
    when :created
      FetchAccessTokenService.new(datastore: datastore).perform(
        installation_id: params[:installation][:id],
        slugs: params[:repositories].map { |repo| repo[:full_name] },
      )
    when :deleted
      # TODO
    end

  when :pull_request
    slug = params[:repository][:full_name]
    pr = Github::PullRequest.from_event(params)

    case params[:action].to_sym
    when :opened, :synchronize
      SyncFilesService.new(datastore: datastore).perform(slug: slug, pr: pr)
    when :closed
      return unless params[:pull_request][:merged]
      MergeService.new(datastore: datastore).perform(slug: slug, pr: pr)
    end
  end
end
