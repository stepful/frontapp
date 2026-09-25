module Frontapp
  class Client
    # One page of a Front collection. `next` is the page_token for the
    # following page, or nil on the last page.
    #
    # A Struct, so both `page.items` and `page[:items]` work.
    Page = Struct.new(:items, :next, keyword_init: true)

    # Lazy enumerator over Front collection pages, yielding Page objects.
    #
    # Requests are made only as the consumer iterates, so memory stays
    # bounded to one page. Examples:
    #
    #   client.conversations.first
    #   # => #<Page items=[...], next="abc">  — one request
    #
    #   client.conversations(page_token: "abc").first
    #   # => next page, one request
    #
    #   client.conversations.flat_map(&:items)
    #   # => all items across pages
    class List < ::Enumerator
    end
  end
end
