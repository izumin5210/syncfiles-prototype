class FetchAccessTokenService
  def initialize(datastore:)
    @datastore = datastore
  end

  def perform(installation_id:, slugs:)
    client = Octokit::Client.new(bearer_token: BEARER_TOKEN)
    resp = client.create_app_installation_access_token(
      installation_id,
      accept: 'application/vnd.github.machine-man-preview+json',
    )

    slugs.each do |slug|
      @datastore.set_token(resp.token, slug: slug)
    end
  end

  def self.create_bearer_token
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

    JWT.encode(payload, private_key, "RS256")
  end

  BEARER_TOKEN = create_bearer_token
end
