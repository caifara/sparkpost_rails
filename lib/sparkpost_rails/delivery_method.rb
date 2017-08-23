module SparkPostRails
  class DeliveryMethod
    require 'net/http'

    attr_accessor :settings, :data, :response

    def initialize(options = {})
      @settings = options
    end

    def deliver!(mail)
      @data = {content: {}}

      prepare_recipients_from mail
      prepare_from_address_from mail
      prepare_reply_to_address_from mail

      prepare_subject_from mail
      prepare_content_from mail

      prepare_options
      prepare_headers

      result = post_to_api

      process_result result
    end

  private
    def prepare_recipients_from mail
      @data[:recipients] = prepare_addresses(mail.to, mail[:to].display_names)
    end

    def prepare_addresses emails, names
      emails = [emails] unless emails.is_a?(Array)
      emails.each_with_index.map {|email, index| prepare_address(email, index, names) }
    end

    def prepare_address email, index, names
      if !names[index].nil?
        { address:  { email: email, name: names[index] } }
      else
        { address: { email: email } }
      end
    end

    def prepare_from_address_from mail
      if !mail[:from].display_names.first.nil?
        from = { email: mail.from.first, name: mail[:from].display_names.first }
      else
        from = { email: mail.from.first }
      end

      @data[:content][:from] = from
    end

    def prepare_reply_to_address_from mail
      unless mail.reply_to.nil?
        @data[:content][:reply_to] = mail.reply_to.first
      end
    end

    def prepare_subject_from mail
      @data[:content][:subject] = mail.subject
    end

    def prepare_content_from mail
      if mail.multipart?
        @data[:content][:html] = cleanse_encoding(mail.html_part.body.to_s) if @data[:content][:html]
        @data[:content][:text] = cleanse_encoding(mail.text_part.body.to_s)
      else
        @data[:content][:text] = cleanse_encoding(mail.body.to_s)
      end
    end

    def cleanse_encoding content
      ::JSON.parse({c: content}.to_json)["c"]
    end

    def prepare_options
      @data[:options] = {
        :open_tracking => SparkPostRails.configuration.track_opens,
        :click_tracking => SparkPostRails.configuration.track_clicks
      }

      unless SparkPostRails.configuration.campaign_id.nil?
        @data[:campaign_id] = SparkPostRails.configuration.campaign_id
      end

      unless SparkPostRails.configuration.return_path.nil?
        @data[:return_path] = SparkPostRails.configuration.return_path
      end
    end

    def prepare_headers
      @headers = {
        "Authorization" => SparkPostRails.configuration.api_key,
        "Content-Type"  => "application/json"
      }
    end

    def post_to_api
      url = "https://api.sparkpost.com/api/v1/transmissions"

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path, @headers)
      request.body = JSON.generate(@data)

      http.request(request)
    end

    def process_result result
      result_data = JSON.parse(result.body)

      if result_data["errors"]
        @response = result_data["errors"]
        raise SparkPostRails::DeliveryException, @response
      else
        @response = result_data["results"]
      end
    end

  end
end
