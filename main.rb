require 'bundler'
Bundler.require

require 'active_support'
require 'active_support/core_ext'

private_pem = File.read(ENV['GITHUB_APP_PRIVATE_KEY_PATH'])
private_key = OpenSSL::PKey::RSA.new(private_pem)
# Generate the JWT
payload = {
  # issued at time
  iat: Time.now.to_i,
  # JWT expiration time (10 minute maximum)
  exp: Time.now.to_i + (10 * 60),
  # GitHub App's identifier
  iss: ENV['GITHUB_APP_ID'],
}

jwt = JWT.encode(payload, private_key, "RS256")

db = {
  tokens: {},
  pulls: {},
}

module Syncfiles
  class NotFound < StandardError; end
end

class GithubClient
  def initialize(access_token:, db:)
    @client = Octokit::Client.new(access_token: access_token)
    @db = db
  end

  def repository(slug)
    @client.repository(slug)
  end

  def fetch_config(slug, ref:)
    content = self.fetch_content(slug, '.syncfiles.yml', ref: ref)
    YAML.load(content).with_indifferent_access
  rescue Octokit::NotFound => e
    pp e
    raise Syncfiles::NotFound
  end

  def fetch_content(slug, path, ref: 'master')
    resp = @client.contents(slug, path: path, ref: ref)
    Base64.decode64(resp.content)
  rescue Octokit::NotFound => e
    pp e
    raise Syncfiles::NotFound
  end

  def sync(slug:, ref:, pull:)
    begin
      cfg = fetch_config(slug, ref: ref)
      cfg[:files].each do |file|
        content = fetch_content(slug, file[:src][:path], ref: ref)
        file[:dests].each do |dest|
          sync_file(slug: dest[:repo], path: dest[:path], content: content, src_repo_slug: slug, src_pull: pull)
        end
      end
    rescue Syncfiles::NotFound
      nil
    end
  end

  private

  def db
    @db
  end

  def sync_file(slug:, path:, content:, src_repo_slug:, src_pull:)
    repo = @client.repository(slug)
    branch = "syncfiles/#{src_repo_slug}/#{src_pull}"
    db[:pulls][src_repo_slug] ||= {}
    db[:pulls][src_repo_slug][src_pull] ||= {}
    title = "Sync #{path} from #{src_repo_slug}"
    body = "from https://github.com/#{src_repo_slug}/pull/#{src_pull}"
    msg = [title, "\n", body].join("\n")

    if db[:pulls][src_repo_slug][src_pull].key? slug
      pull = @client.pull_requsets(slug, db[:pulls][src_repo_slug][src_pull])
      dest_content = self.fetch_content(slug, path, ref: pull.head.ref)
      return if content == dest_content
      @client.update_contents(slug, path, msg, content, branch: branch)
    else
      begin
        dest_content = self.fetch_content(slug, path)
        return if content == dest_content
      rescue Syncfiles::NotFound
        @client.create_ref(
          slug,
          "heads/" + branch,
          @client.ref(slug, "heads/" + repo.default_branch).object.sha,
        )
        @client.create_contents(slug, path, msg, content, branch: branch)
        resp = @client.create_pull_request(slug, repo.default_branch, branch, title, body)
        db[:pulls][src_repo_slug][src_pull][slug] = resp.number
      end
    end
  end
end

post '/webhook' do
  params = JSON.parse(request.body.read).with_indifferent_access
  case request.env['HTTP_X_GITHUB_EVENT']&.to_sym
  when :installation
    c = Octokit::Client.new(bearer_token: jwt)
    resp = c.create_app_installation_access_token(
      params[:installation][:id],
      accept: 'application/vnd.github.machine-man-preview+json',
    )
    params[:repositories].each do |repo|
      db[:tokens][repo[:full_name]] = { token: resp.token, expired_at: resp.expired_at }
    end
  when :pull_request
    case params[:action].to_sym
    when :opened, :synchronize
      slug = params[:repository][:full_name]
      GithubClient.new(access_token: db[:tokens][slug][:token], db: db).sync(
        slug: slug,
        pull: params[:number],
        ref:  params[:pull_request][:head][:ref],
      )
    end
  end
end
