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
