module Frontapp
  class Client
    # Front's rate-limit headers for one response. The budget is per API token.
    # `retry_after` and `tier` (the guard tripped, nil for the global one) come only on a 429.
    RateLimit = Struct.new(:limit, :remaining, :reset_at, :retry_after, :tier, keyword_init: true) do
      # Nil when the response carries no rate-limit headers.
      def self.from_headers(headers)
        limit = headers["x-ratelimit-limit"]
        remaining = headers["x-ratelimit-remaining"]
        retry_after = headers["retry-after"]
        return nil if limit.nil? && remaining.nil? && retry_after.nil?

        reset = headers["x-ratelimit-reset"]
        new(
          limit: limit&.to_i,
          remaining: remaining&.to_i,
          reset_at: reset && Time.at(reset.to_f),
          retry_after: retry_after&.to_i,
          tier: headers["x-front-tier"]
        ).freeze
      end
    end

    # Runs on every response, so a 429 is recorded before the client raises.
    class RateLimitTracker < Faraday::Middleware
      def initialize(app, on_rate_limit)
        super(app)
        @on_rate_limit = on_rate_limit
      end

      def on_complete(env)
        rate_limit = RateLimit.from_headers(env.response_headers)
        @on_rate_limit.call(rate_limit) if rate_limit
      end
    end
  end
end
