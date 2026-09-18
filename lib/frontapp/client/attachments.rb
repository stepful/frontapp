module Frontapp
  class Client
    module Attachments

      # Parameters
      # Name                Type    Description
      # ----------------------------------------------------------
      # attachment_link_id  string  Id of the requested attachment
      # ----------------------------------------------------------
      def download_attachment(attachment_link_id)
        get_raw("download/#{attachment_link_id}")
      end

      # Parameters
      # Name                Type    Description
      # ----------------------------------------------------------
      # attachment_link_id  string  Id of the requested attachment
      # ----------------------------------------------------------
      #
      # As download_attachment, but returns the whole response. Proxying a
      # download to a browser needs the Content-Type and Content-Disposition
      # that the body alone does not carry.
      def download_attachment_response(attachment_link_id)
        get_raw_response("download/#{attachment_link_id}")
      end
    end
  end
end
