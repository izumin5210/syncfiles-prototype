class SyncFilesService
  def initialize(datastore:)
    @datastore = datastore
  end

  def perform(slug:, pr:)
    @client = Github::Client.new(access_token: @datastore.token_for(slug: slug))

    begin
      cfg = @client.find_config(slug, ref: pr.branch)
      cfg.entries.each do |entry|
        content = @client.find_entry(slug, entry.src.path, ref: ref).content
        entry.dests.each do |dest|
          sync_file(dest: dest, content: content, src_slug: slug, src_pr: pr)
        end
      end
    rescue Github::NotFound
      nil
    end
  end

  private

  def sync_file(dest:, content:, src_slug:, src_pr:)
    repo = @client.repository(dest.repo)
    branch = "syncfiles/#{src_slug}/pull/#{pr.number}"
    title = "Sync #{dest.path} from #{src_slug}"
    body = "from https://github.com/#{src_slug}/pull/#{src_pr.number}"
    msg = [title, "\n", "from https://github.com/#{src_slug}/commit/#{src_pr.number}"].join("\n")

    branch = @client.find_or_create_branch(dest.repo, branch)

    begin
      dest_entry = @client.find_entry(dest.repo, dest.path, ref: branch)
      return if content == dest_entry.content
      @client.update_contents(dest.repo, dest.path, msg, dest_entry.sha, content, branch: branch)
    rescue NotFound
      @client.create_contents(dest.repo, dest.path, msg, content, branch: branch)
    end

    if branch.new_branch?
      @client.create_pull_request(dest.repo, repo.default_branch, branch, title, body)
    end
  end
end
