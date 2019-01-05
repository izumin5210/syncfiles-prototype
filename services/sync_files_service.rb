class SyncFilesService
  def initialize(datastore:)
    @datastore = datastore
  end

  def perform(slug:, pr:)
    @client = Github::Client.new(access_token: @datastore.token_for(slug: slug))

    begin
      cfg = @client.find_config(slug, ref: pr.branch.ref)
      cfg.entries.each do |entry|
        content = @client.find_entry(slug, entry.src.path, ref: pr.branch.ref).content
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
    branch = "syncfiles/#{src_slug}/pull/#{src_pr.number}"
    title = "Sync #{dest.path} from #{src_slug}"
    body = "from https://github.com/#{src_slug}/pull/#{src_pr.number}"
    msg = [title, "\n", "from https://github.com/#{src_slug}/commit/#{src_pr.number}"].join("\n")

    branch = @client.find_or_create_branch(dest.repo, branch)
    @client.create_or_update_content(dest.repo, dest.path, content, message: msg, ref: branch.ref)

    if branch.new_branch?
      @client.create_pull_request(dest.repo, branch.name, title: title, body: body)
    end
  end
end
