require 'uri'
require 'faraday'
require 'faraday/multipart'
require 'json'
require_relative 'client/attachments'
require_relative 'client/channels'
require_relative 'client/comments'
require_relative 'client/contact_groups'
require_relative 'client/contacts'
require_relative 'client/conversations'
require_relative 'client/events'
require_relative 'client/inboxes'
require_relative 'client/messages'
require_relative 'client/rules'
require_relative 'client/tags'
require_relative 'client/teammates'
require_relative 'client/teams'
require_relative 'client/topics'
require_relative 'client/links'
require_relative 'client/exports'
require_relative 'error'
require_relative 'version'

module Frontapp
  # Raised before any request is made when the attachments on a single message
  # exceed Front's per-message limit.
  class AttachmentsTooLargeError < ArgumentError; end

  class Client

    # Front rejects messages whose attachments total more than 25 MB.
    MAX_ATTACHMENTS_SIZE = 25 * 1024 * 1024

    include Frontapp::Client::Attachments
    include Frontapp::Client::Channels
    include Frontapp::Client::Comments
    include Frontapp::Client::ContactGroups
    include Frontapp::Client::Contacts
    include Frontapp::Client::Conversations
    include Frontapp::Client::Events
    include Frontapp::Client::Inboxes
    include Frontapp::Client::Messages
    include Frontapp::Client::Rules
    include Frontapp::Client::Tags
    include Frontapp::Client::Teammates
    include Frontapp::Client::Teams
    include Frontapp::Client::Topics
    include Frontapp::Client::Links
    include Frontapp::Client::Exports

    def initialize(options={})
      auth_token = options[:auth_token]
      user_agent = options[:user_agent] || "Frontapp Ruby Gem #{VERSION}"
      @connection = Faraday.new(
        url: base_url,
        headers: {
          Accept: "application/json",
          Authorization: "Bearer #{auth_token}",
          "User-Agent": user_agent
        }) do |f|
        # Only engages for Hash bodies posted as multipart/form-data (see
        # create_multipart). JSON requests set a String body and are untouched.
        f.request(:multipart)
        # Faraday adds url_encoded by default only when no block is given;
        # keep it so the middleware stack is unchanged for existing requests.
        f.request(:url_encoded)
      end
    end

    def list(path, params = {}, &block)
      paginate = params.delete(:paginate)
      paginate = true if paginate.nil?

      items = block ? nil : []

      query = format_query(params)
      url = query.empty? ? path : "#{path}?#{query}"

      while url
        res = @connection.get(url)
        raise Error.from_response(res) unless res.success?
        response = JSON.parse(res.body)
        results = response["_results"] || []
        url = paginate ? response["_pagination"]&.dig("next") : nil

        unless results.empty?
          if items
            items.concat(results)
          else
            block.call(results)
          end
        end
      end

      items
    end

    # One page, with Front's cursor. list walks every page and discards
    # _pagination.next, so a caller can never resume where it left off.
    #
    # @return [Hash] :items, and :next — the page_token for the following page
    def list_page(path, params = {})
      # paginate is list's control key, not a Front param, so a hash built for
      # list can be handed here without it reaching the query string.
      params = params.except(:paginate)

      query = format_query(params)
      url = query.empty? ? path : "#{path}?#{query}"

      res = @connection.get(url)
      raise Error.from_response(res) unless res.success?
      response = JSON.parse(res.body)

      {
        items: response["_results"] || [],
        next: next_page_token(response["_pagination"]&.dig("next"))
      }
    end

    def get(path)
      res = @connection.get(path)
      raise Error.from_response(res) unless res.success?
      JSON.parse(res.body)
    end

    def get_plain(path)
      res = @connection.get path do |req|
        req.headers[:accept] = 'text/plain'
      end

      raise Error.from_response(res) unless res.success?
      res.body.to_s
    end

    def get_raw(path)
      get_raw_response(path).body
    end

    # Returns the whole response rather than just the body, so callers that
    # re-serve a payload can read Content-Type and Content-Disposition off it.
    def get_raw_response(path)
      res = @connection.get(path)
      raise Error.from_response(res) unless res.success?
      res
    end

    # Posts body as JSON. Returns the parsed response body, or nil when the
    # response has no body.
    def create(path, body)
      res = @connection.post path do |req|
        req.headers[:content_type] = 'application/json'
        req.body = body.to_json
      end

      raise Error.from_response(res) unless res.success?
      parse_body(res)
    end

    # Posts params as multipart/form-data. Front only accepts file attachments
    # this way. Nested hashes and arrays are flattened into the form keys Front
    # expects (`options[tags][]`, `to[]`), nil values are dropped since form
    # data has no null, and each entry of params[:attachments] is sent as an
    # `attachments[]` file part carrying its filename and content type.
    #
    # Attachments may be Faraday::Multipart::FilePart objects (aliased as
    # Faraday::UploadIO), file-like objects that respond to #read and
    # #original_filename (such as ActionDispatch::Http::UploadedFile), or
    # hashes with :io, :filename and :content_type. Each IO is rewound before
    # the body is built, so a handle that has already been read is sent in
    # full. Raises AttachmentsTooLargeError before sending when the combined
    # attachment size exceeds MAX_ATTACHMENTS_SIZE.
    #
    # Returns the parsed JSON body, or nil when Front replies with no body.
    def create_multipart(path, params)
      body = multipart_body(params)
      res = @connection.post path do |req|
        req.headers[:content_type] = 'multipart/form-data'
        req.body = body
      end

      raise Error.from_response(res) unless res.success?
      parse_body(res)
    end

    def create_without_response(path, body)
      res = @connection.post path do |req|
           req.headers[:content_type] = 'application/json'
           req.body = body.to_json
         end
      raise Error.from_response(res) unless res.success?
    end

    def update(path, body)
      res = @connection.patch path do |req|
        req.headers[:content_type] = 'application/json'
        req.body = body.to_json
      end
      raise Error.from_response(res) unless res.success?
    end

    def delete(path, body = {})
      res = @connection.delete path do |req|
        req.headers[:content_type] = 'application/json'
        req.body = body.to_json
      end
      raise Error.from_response(res) unless res.success?
    end

    # Front returns the next page as a whole URL; callers want only the token.
    private def next_page_token(next_url)
      return nil if next_url.nil? || next_url.empty?

      query = URI.parse(next_url).query
      return nil if query.nil? || query.empty?

      token = URI.decode_www_form(query).to_h["page_token"]
      token.nil? || token.empty? ? nil : token
    rescue URI::InvalidURIError
      nil
    end

    private def format_query(params)
      res = []
      q = params.delete(:q)
      if q && q.is_a?(Hash)
        res << q.map do |k, v|
          case v
          when Symbol, String
            "q[#{k}]=#{URI.encode_www_form_component(v)}"
          when Array
            v.map { |c| "q[#{k}][]=#{URI.encode_www_form_component(c.to_s)}" }.join("&")
          else
            "q[#{k}]=#{URI.encode_www_form_component(v.to_s)}"
          end
        end
      end
      res << params.map {|k,v| "#{k}=#{URI.encode_www_form_component(v.to_s)}"}
      res.join("&")
    end

    private def multipart_body(params)
      attachments = params[:attachments] || []
      unless attachments.is_a?(Array)
        raise ArgumentError, "attachments must be an Array, got #{attachments.class}"
      end
      parts = attachments.map { |attachment| upload_part_for(attachment) }

      total = parts.sum { |part| attachment_size(part) }
      if total > MAX_ATTACHMENTS_SIZE
        raise AttachmentsTooLargeError,
              "Attachments total #{total} bytes; Front allows at most " \
              "#{MAX_ATTACHMENTS_SIZE} bytes (25 MB) per message"
      end
      parts.each { |part| part.io.rewind if part.io.respond_to?(:rewind) }

      body = compact_params(params.reject { |key, _| key.to_s == "attachments" })
      body[:attachments] = parts unless parts.empty?
      body
    end

    private def upload_part_for(attachment)
      return attachment if attachment.is_a?(Faraday::Multipart::FilePart)

      if attachment.respond_to?(:read) && attachment.respond_to?(:original_filename)
        content_type = attachment.content_type if attachment.respond_to?(:content_type)
        return Faraday::Multipart::FilePart.new(attachment,
                                                content_type || "application/octet-stream",
                                                attachment.original_filename)
      end

      unless attachment.is_a?(Hash)
        raise ArgumentError,
              "attachments must be Faraday::UploadIO objects, file-like objects " \
              "responding to #read and #original_filename, or hashes with " \
              ":io, :filename and :content_type, got #{attachment.class}"
      end

      io = attachment[:io] || attachment["io"]
      filename = attachment[:filename] || attachment["filename"]
      content_type = attachment[:content_type] || attachment["content_type"] || "application/octet-stream"
      raise ArgumentError, "attachment :io must respond to #read" unless io.respond_to?(:read)
      raise ArgumentError, "attachment :filename is required" if filename.to_s.empty?

      Faraday::Multipart::FilePart.new(io, content_type, filename)
    end

    # Best-effort size of an upload part; unknown sizes count as 0 and are
    # left for Front to enforce.
    private def attachment_size(part)
      io = part.io
      if io.respond_to?(:size)
        io.size.to_i
      elsif io.respond_to?(:stat)
        io.stat.size
      else
        0
      end
    end

    private def parse_body(res)
      res.body.to_s.empty? ? nil : JSON.parse(res.body)
    end

    # Deep-removes nil values: JSON sends them as null, form data has no null.
    private def compact_params(value)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), result|
          result[k] = compact_params(v) unless v.nil?
        end
      when Array
        value.compact.map { |v| compact_params(v) }
      else
        value
      end
    end

    private def base_url
      "https://api2.frontapp.com/"
    end

  end
end
