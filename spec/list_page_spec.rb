require 'spec_helper'
require 'frontapp'

RSpec.describe 'list_page' do

  let(:headers) { json_headers }
  let(:frontapp) { Frontapp::Client.new(auth_token: auth_token) }
  let(:contact_id) { "ctc_55c8c149" }

  def page_response(next_url)
    pagination = next_url.nil? ? "null" : %Q{"#{next_url}"}
    %Q{
{
  "_pagination": { "next": #{pagination} },
  "_results": [
    { "id": "cnv_55c8c149", "subject": "You broke my heart, Hubert." }
  ]
}
    }
  end

  it 'returns the page and the token for the next one' do
    next_url = "#{base_url}/contacts/#{contact_id}/conversations?limit=10&page_token=abc123"
    stub_request(:get, "#{base_url}/contacts/#{contact_id}/conversations?limit=10")
      .with(headers: headers)
      .to_return(status: 200, body: page_response(next_url), headers: {})

    page = frontapp.list_page("contacts/#{contact_id}/conversations", { limit: 10 })

    expect(page[:items].map { |c| c["id"] }).to eq(["cnv_55c8c149"])
    expect(page[:next]).to eq("abc123")
  end

  it 'reports no token on the last page' do
    stub_request(:get, "#{base_url}/links")
      .with(headers: headers)
      .to_return(status: 200, body: page_response(nil), headers: {})

    expect(frontapp.list_page("links")[:next]).to be_nil
  end

  it 'reports no token when the next url carries none' do
    stub_request(:get, "#{base_url}/links")
      .with(headers: headers)
      .to_return(status: 200, body: page_response("#{base_url}/links?limit=10"), headers: {})

    expect(frontapp.list_page("links")[:next]).to be_nil
  end

  it 'does not follow the cursor the way list does' do
    stub_request(:get, "#{base_url}/links")
      .with(headers: headers)
      .to_return(status: 200, body: page_response("#{base_url}/links?page_token=abc123"), headers: {})

    frontapp.list_page("links")

    expect(a_request(:get, "#{base_url}/links")).to have_been_made.once
  end

  it 'sends the page token the caller was handed' do
    stub_request(:get, "#{base_url}/links?page_token=abc123")
      .with(headers: headers)
      .to_return(status: 200, body: page_response(nil), headers: {})

    frontapp.list_page("links", { page_token: "abc123" })

    expect(a_request(:get, "#{base_url}/links?page_token=abc123")).to have_been_made
  end

  describe 'the widened whitelists' do
    it 'passes limit and page_token through get_contact_conversations' do
      stub_request(:get, "#{base_url}/contacts/#{contact_id}/conversations?limit=10&page_token=abc123")
        .with(headers: headers)
        .to_return(status: 200, body: page_response(nil), headers: {})

      frontapp.get_contact_conversations(contact_id, { limit: 10, page_token: "abc123" })

      expect(
        a_request(:get, "#{base_url}/contacts/#{contact_id}/conversations?limit=10&page_token=abc123")
      ).to have_been_made
    end

    it 'still drops params Front does not accept' do
      stub_request(:get, "#{base_url}/contacts/#{contact_id}/conversations?limit=10")
        .with(headers: headers)
        .to_return(status: 200, body: page_response(nil), headers: {})

      frontapp.get_contact_conversations(contact_id, { limit: 10, nonsense: "x" })

      expect(
        a_request(:get, "#{base_url}/contacts/#{contact_id}/conversations?limit=10")
      ).to have_been_made
    end
  end
end
