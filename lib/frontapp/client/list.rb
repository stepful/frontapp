module Frontapp
  class Client
    # Lazy enumerator over Front collection pages.
    #
    # Each yielded value is a Hash:
    #   { items: [ ... ], next: page_token_or_nil }
    #
    # Requests are made only as the consumer iterates, so memory stays
    # bounded to one page. Examples:
    #
    #   client.conversations.first
    #   # => { items: [...], next: "abc" }  — one request
    #
    #   client.conversations(page_token: "abc").first
    #   # => next page, one request
    #
    #   client.conversations.flat_map { |page| page[:items] }
    #   # => all items across pages
    class List < ::Enumerator
    end
  end
end
