module Github
  class Error < StandardError
    def initialize(e = nil)
      super(e)
      set_backtrace(e.backtrace) if e
    end
  end

  class NotFound < Error; end

  class Branch < Struct.new(:name, :ref, :sha, :new_branch, keyword_init: true)
    def self.from_ref(ref, name: nil, new_branch: false)
      new(
        name:       name.presence || ref.gsub(%r!^refs/heads/!, ''),
        ref:        ref.ref,
        sha:        ref.object.sha,
        new_branch: new_branch,
      )
    end

    def new_branch?
      !!@new_branch
    end
  end

  class PullRequest < Struct.new(:number, :branch, keyword_init: true)
    def self.from_event(payload)
      head = payload[:pull_request][:head]
      branch = Branch.new(
        name: head[:ref],
        ref:  "refs/heads/" + head[:ref],
        sha:  head[:sha],
      )
      new(
        number:   payload[:number],
        branch: branch,
      )
    end
  end

  Entry = Struct.new(:path, :content, :sha, keyword_init: true)

  class Client
    def initialize(access_token:)
      @client = Octokit::Client.new(access_token: access_token)
      @repositories = {}
      @entries = {}
      @branches = {}
    end

    def find_config(slug, ref:)
      content = find_entry(slug, '.syncfiles.yml', ref: ref).content
      Config.new(YAML.load(content))
    rescue Octokit::NotFound => e
      Syncfiles.logger.debug "#{slug}@#{ref} does not have .syncfiles.yml"
      raise NotFound.new(e)
    end

    def find_repository(slug)
      @repositories[slug] ||= @client.repository(slug)
    rescue Octokit::NotFound => e
      Syncfiles.logger.debug "Repository #{slug} does not exist"
      raise NotFound.new(e)
    end

    def find_entry(slug, path, ref: 'master')
      @entries[slug] ||= {}
      @entries[slug][ref] ||= {}
      @entries[slug][ref][path] ||=
        begin
          resp = @client.contents(slug, path: path, ref: ref)
          Entry.new(
            path:    resp.path,
            content: Base64.decode64(resp.content),
            sha:     resp.sha,
          )
        end
    rescue Octokit::NotFound => e
      Syncfiles.logger.debug "#{slug}@#{ref} does not have #{path}"
      raise NotFound.new(e)
    end

    def find_branch(slug, branch_name)
      @branches[slug] ||= {}
      @branches[slug][branch_name] ||=
        begin
          ref = @client.ref(slug, "heads/" + branch_name)
          Branch.from_ref(ref, name: branch_name)
        end
    rescue Octokit::NotFound => e
      Syncfiles.logger.debug "#{slug} does not have #{branch_name} branch"
      raise NotFound.new(e)
    end

    def find_or_create_branch(slug, branch_name)
      find_branch(slug, branch_name)
    rescue NotFound
      repo = find_repository(slug)
      ref = @client.create_ref(
        slug,
        "heads/" + branch_name,
        find_branch(slug, repo.default_branch).sha,
      )
      Syncfiles.logger.debug "#{branch_name} branch was created on #{slug}"
      Branch.from_ref(ref, name: branch_name, new_branch: true).tap do |b|
        @branches[slug][branch_name] = b
      end
    end

    def create_or_update_content(slug, path, content, message:, ref: 'master')
      begin
        dest_entry = find_entry(slug, path, ref: ref)
        if content == dest_entry.content
          Syncfiles.logger.debug "#{slug}@#{branch}:#{dest.path} was not updated"
          return
        end
        @client.update_contents(slug, path, message, dest_entry.sha, content, branch: ref)
        Syncfiles.logger.debug "#{slug}@#{branch}:#{dest.path} was updated"
      rescue Github::NotFound
        @client.create_contents(slug, path, message, content, branch: ref)
        Syncfiles.logger.debug "#{slug}@#{branch}:#{dest.path} was created"
      end
    end

    def create_pull_request(slug, head, title:, body:, base: nil)
      if base.blank?
        repo = @client.find_repository(slug)
        base = repo.default_branch
      end
      resp = @client.create_pull_request(slug, base, head, title, body)
      Syncfiles.logger.debug "pull request ##{resp[:number]} was created on #{slug}"
    end
  end
end
