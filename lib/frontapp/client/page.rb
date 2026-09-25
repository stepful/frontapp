module Frontapp
  class Client
    # One page of a Front collection, as yielded by the Enumerator that
    # Client#list returns. `next_page_token` is the page_token for the
    # following page, or nil on the last page.
    #
    # A Struct, so both `page.items` and `page[:items]` work.
    Page = Struct.new(:items, :next_page_token, keyword_init: true)
  end
end
