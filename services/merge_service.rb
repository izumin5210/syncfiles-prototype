class MergeService
  def initialize(datastore:)
    @datastore = datastore
  end

  def perform(slug:, pr:)
    @client = Github::Client.new(access_token: @datastore.token_for(slug: slug))
    begin
      cfg = @client.find_config(slug, ref: pr.branch)
      branch = "syncfiles/#{slug}/pull/#{pr.number}"
      cfg.entries.each do |entry|
        entry.dests.each do |dest|
          prs = @client.pull_requests(dest.repo, state: :open, head: branch, sort: :created, direction: :desc)
          next if prs.empty?
          @client.merge_pull_request(dest.repo, prs[0][:number])
        end
      end
    rescue Github::NotFound
      nil
    end
  end
end
