require 'spec_helper'
require 'frontapp'

RSpec.describe 'list' do

  let(:headers) { json_headers }
  let(:frontapp) { Frontapp::Client.new(auth_token: auth_token) }
  let(:contact_id) { "ctc_55c8c149" }

  def page_response(ids:, next_url: nil)
    pagination = next_url.nil? ? "null" : %Q{"#{next_url}"}
    results = ids.map { |id| %Q[{ "id": "#{id}" }] }.join(",\n    ")
    %Q{
{
  "_pagination": { "next": #{pagination} },
  "_results": [
    #{results}
  ]
}
    }
  end

  it 'returns a lazy List enumerator of pages' do
    stub_request(:get, "#{base_url}/links")
      .with(headers: headers)
      .to_return(status: 200, body: page_response(ids: ["top_1"]), headers: {})

    result = frontapp.list("links")

    expect(result).to be_a(Frontapp::Client::List)
    expect(a_request(:get, "#{base_url}/links")).not_to have_been_made

    page = result.first
    expect(page[:items].map { |r| r["id"] }).to eq(["top_1"])
    expect(page[:next]).to be_nil
    expect(a_request(:get, "#{base_url}/links")).to have_been_made.once
  end

  it 'yields the page token so a caller can resume later' do
    next_url = "#{base_url}/links?limit=10&page_token=abc123"
    stub_request(:get, "#{base_url}/links?limit=10")
      .with(headers: headers)
      .to_return(status: 200, body: page_response(ids: ["top_1"], next_url: next_url), headers: {})

    page = frontapp.list("links", { limit: 10 }).first

    expect(page[:next]).to eq("abc123")
  end

  it 'sends a caller-supplied page_token' do
    stub_request(:get, "#{base_url}/links?page_token=abc123")
      .with(headers: headers)
      .to_return(status: 200, body: page_response(ids: ["top_2"]), headers: {})

    page = frontapp.list("links", { page_token: "abc123" }).first

    expect(page[:items].map { |r| r["id"] }).to eq(["top_2"])
    expect(a_request(:get, "#{base_url}/links?page_token=abc123")).to have_been_made
  end

  it 'follows pagination only as the consumer iterates' do
    page1_next = "#{base_url}/links?page_token=tok2"
    stub_request(:get, "#{base_url}/links")
      .with(headers: headers)
      .to_return(status: 200, body: page_response(ids: ["top_1"], next_url: page1_next), headers: {})
    stub_request(:get, "#{base_url}/links?page_token=tok2")
      .with(headers: headers)
      .to_return(status: 200, body: page_response(ids: ["top_2"]), headers: {})

    enum = frontapp.list("links")
    first = enum.next

    expect(first[:items].map { |r| r["id"] }).to eq(["top_1"])
    expect(first[:next]).to eq("tok2")
    expect(a_request(:get, "#{base_url}/links")).to have_been_made.once
    expect(a_request(:get, "#{base_url}/links?page_token=tok2")).not_to have_been_made

    second = enum.next
    expect(second[:items].map { |r| r["id"] }).to eq(["top_2"])
    expect(second[:next]).to be_nil
    expect(a_request(:get, "#{base_url}/links?page_token=tok2")).to have_been_made.once
  end

  it 'collects all items across pages with flat_map' do
    page1_next = "#{base_url}/links?page_token=tok2"
    stub_request(:get, "#{base_url}/links")
      .with(headers: headers)
      .to_return(status: 200, body: page_response(ids: ["top_1"], next_url: page1_next), headers: {})
    stub_request(:get, "#{base_url}/links?page_token=tok2")
      .with(headers: headers)
      .to_return(status: 200, body: page_response(ids: ["top_2"]), headers: {})

    items = frontapp.list("links").flat_map { |page| page[:items] }

    expect(items.map { |r| r["id"] }).to eq(["top_1", "top_2"])
  end

  it 'stops after one page when paginate is false' do
    page1_next = "#{base_url}/links?page_token=tok2"
    stub_request(:get, "#{base_url}/links")
      .with(headers: headers)
      .to_return(status: 200, body: page_response(ids: ["top_1"], next_url: page1_next), headers: {})

    pages = frontapp.list("links", { paginate: false }).to_a

    expect(pages.size).to eq(1)
    expect(pages.first[:next]).to eq("tok2")
    expect(a_request(:get, "#{base_url}/links?page_token=tok2")).not_to have_been_made
  end

  it 'reports no token when the next url carries none' do
    stub_request(:get, "#{base_url}/links")
      .with(headers: headers)
      .to_return(status: 200, body: page_response(ids: ["top_1"], next_url: "#{base_url}/links?limit=10"), headers: {})

    expect(frontapp.list("links").first[:next]).to be_nil
  end

  it 'yields pages to a block' do
    stub_request(:get, "#{base_url}/links")
      .with(headers: headers)
      .to_return(status: 200, body: page_response(ids: ["top_1"]), headers: {})

    seen = []
    frontapp.list("links") { |page| seen << page[:items].map { |r| r["id"] } }

    expect(seen).to eq([["top_1"]])
  end

  describe 'get_contact_conversations' do
    it 'returns a List and passes limit and page_token through' do
      url = "#{base_url}/contacts/#{contact_id}/conversations" \
            "?q[statuses][]=archived&limit=10&page_token=abc123"
      stub_request(:get, url)
        .with(headers: headers)
        .to_return(
          status: 200,
          body: page_response(ids: ["cnv_1"], next_url: "#{base_url}/contacts/#{contact_id}/conversations?page_token=next"),
          headers: {}
        )

      result = frontapp.get_contact_conversations(
        contact_id,
        { q: { statuses: [:archived] }, limit: 10, page_token: "abc123" }
      )

      expect(result).to be_a(Frontapp::Client::List)
      page = result.first
      expect(page[:items].map { |c| c["id"] }).to eq(["cnv_1"])
      expect(page[:next]).to eq("next")
      expect(a_request(:get, url)).to have_been_made
    end

    it 'drops params Front does not accept' do
      stub_request(:get, "#{base_url}/contacts/#{contact_id}/conversations?limit=10")
        .with(headers: headers)
        .to_return(status: 200, body: page_response(ids: ["cnv_1"]), headers: {})

      frontapp.get_contact_conversations(contact_id, { limit: 10, nonsense: "x" }).first

      expect(
        a_request(:get, "#{base_url}/contacts/#{contact_id}/conversations?limit=10")
      ).to have_been_made
    end
  end

end
