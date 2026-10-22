require 'spec_helper'
require 'frontapp'

RSpec.describe 'Rate limit' do
  let(:headers) { json_headers }
  let(:rate_limit_headers) {
    { "x-ratelimit-limit" => "200", "x-ratelimit-remaining" => "37", "x-ratelimit-reset" => "1792609800" }
  }

  it "tracks the latest response's rate limit and keeps it through a response without one" do
    stub_request(:get, "#{base_url}/contacts/1").
      with(headers: headers).
      to_return(status: 200, body: "{}", headers: rate_limit_headers)
    stub_request(:get, "#{base_url}/contacts/2").
      with(headers: headers).
      to_return(status: 200, body: "{}")
    seen = []
    frontapp = Frontapp::Client.new(auth_token: auth_token, on_rate_limit: ->(rate_limit) { seen << rate_limit })

    frontapp.get_contact(1)
    frontapp.get_contact(2)

    expected = Frontapp::Client::RateLimit.new(
      limit: 200, remaining: 37, reset_at: Time.at(1792609800), retry_after: nil, tier: nil
    )
    expect(frontapp.rate_limit).to eq(expected)
    expect(seen).to eq([expected])
  end

  it "exposes Retry-After and the tripped tier on a 429" do
    stub_request(:patch, "#{base_url}/contacts/1").
      to_return(
        status: 429,
        body: "{}",
        headers: rate_limit_headers.merge("x-ratelimit-remaining" => "0", "retry-after" => "12", "x-front-tier" => "tier1")
      )
    frontapp = Frontapp::Client.new(auth_token: auth_token)

    error = frontapp.update_contact!(1, {}) rescue $!

    expect(error).to be_a(Frontapp::TooManyRequestsError)
    expect(error.rate_limit).to have_attributes(remaining: 0, retry_after: 12, tier: "tier1")
    expect(frontapp.rate_limit).to eq(error.rate_limit)
  end
end
