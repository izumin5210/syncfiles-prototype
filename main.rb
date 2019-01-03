require 'bundler'
Bundler.require

require 'active_support'
require 'active_support/core_ext'

module Syncfiles
  class NotFound < StandardError; end
end

class Datastore
  PATH = 'data.json'

  def initialize
    @data = JSON.parse(open(PATH).read).with_indifferent_access
  rescue Errno::ENOENT
    @data = {
      tokens: {},
      pulls: {},
    }.with_indifferent_access
    save
  end

  def token_for(slug:)
    @data.dig(:tokens, slug, :token)
  end

  def set_token(token, slug:)
    @data[:tokens][slug] ||= {}
    @data[:tokens][slug][:token] = token
    save
  end

  private

  def save
    open(PATH, 'w') do |f|
      f.puts JSON.pretty_generate(@data)
    end
  end
end

class GithubClient
  Entry = Struct.new(:path, :content, :sha, keyword_init: true)

  def initialize(access_token:)
    @client = Octokit::Client.new(access_token: access_token)
  end

  def sync(slug:, ref:, pull:, sha:)
    begin
      cfg = fetch_config(slug, ref: ref)
      cfg[:files].each do |file|
        content = fetch_entry(slug, file[:src][:path], ref: ref).content
        file[:dests].each do |dest|
          sync_file(slug: dest[:repo], path: dest[:path], content: content, src_repo_slug: slug, src_pull: pull, src_ref: ref, src_sha: sha)
        end
      end
    rescue Syncfiles::NotFound
      nil
    end
  end

  private

  def fetch_config(slug, ref:)
    content = fetch_entry(slug, '.syncfiles.yml', ref: ref).content
    YAML.load(content).with_indifferent_access
  rescue Octokit::NotFound => e
    pp e
    raise Syncfiles::NotFound
  end

  def fetch_entry(slug, path, ref: 'master')
    resp = @client.contents(slug, path: path, ref: ref)
    Entry.new(
      path:    resp.path,
      content: Base64.decode64(resp.content),
      sha:     resp.sha,
    )
  rescue Octokit::NotFound => e
    pp e
    raise Syncfiles::NotFound
  end

  def sync_file(slug:, path:, content:, src_repo_slug:, src_pull:, src_ref:, src_sha:)
    repo = @client.repository(slug)
    branch = "syncfiles/#{src_repo_slug}/#{src_pull}"
    title = "Sync #{path} from #{src_repo_slug}"
    body = "from https://github.com/#{src_repo_slug}/pull/#{src_pull}"
    msg = [title, "\n", "from https://github.com/#{src_repo_slug}/commit/#{src_sha}"].join("\n")

    new_pull = false

    begin
      @client.ref(slug, "heads/" + branch)
    rescue Octokit::NotFound
      new_pull = true
      @client.create_ref(
        slug,
        "heads/" + branch,
        @client.ref(slug, "heads/" + repo.default_branch).object.sha,
      )
    end

    begin
      dest_entry = fetch_entry(slug, path, ref: branch)
      return if content == dest_entry.content
      @client.update_contents(slug, path, msg, dest_entry.sha, content, branch: branch)
    rescue Syncfiles::NotFound
      @client.create_contents(slug, path, msg, content, branch: branch)
    end

    if new_pull
      @client.create_pull_request(slug, repo.default_branch, branch, title, body)
    end
  end
end

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

datastore = Datastore.new

post '/webhook' do
  params = JSON.parse(request.body.read).with_indifferent_access
  case request.env['HTTP_X_GITHUB_EVENT']&.to_sym
  when :installation
    case params[:action].to_sym
    when :created
      c = Octokit::Client.new(bearer_token: jwt)
      resp = c.create_app_installation_access_token(
        params[:installation][:id],
        accept: 'application/vnd.github.machine-man-preview+json',
      )
      params[:repositories].each do |repo|
        datastore.set_token(resp.token, slug: repo[:full_name])
      end
    when :deleted
    end
  when :pull_request
    case params[:action].to_sym
    when :opened, :synchronize
      slug = params[:repository][:full_name]
      GithubClient.new(access_token: datastore.token_for(slug: slug)).sync(
        slug: slug,
        pull: params[:number],
        ref:  params[:pull_request][:head][:ref],
        sha:  params[:pull_request][:head][:sha],
      )
    end
  end
end
