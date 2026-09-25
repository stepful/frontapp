module Frontapp
  class Client
    # One page of a Front collection, as yielded by the Enumerator that
    # Client#list returns. `next` is the page_token for the following page,
    # or nil on the last page.
    #
    # A Struct, so both `page.items` and `page[:items]` work.
    Page = Struct.new(:items, :next, keyword_init: true)
  end
end
