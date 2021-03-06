require 'mediawiki_selenium/support/sauce'

require 'rest_client'
require 'uri'

module MediawikiSelenium
  # Constructs remote browser sessions to be run via Sauce Labs. Adds the
  # following configuration bindings to the factory.
  #
  #  - sauce_ondemand_username
  #  - sauce_ondemand_access_key
  #  - platform
  #  - version
  #
  module RemoteBrowserFactory
    REQUIRED_CONFIG = [:sauce_ondemand_username, :sauce_ondemand_access_key]
    URL = 'http://ondemand.saucelabs.com/wd/hub'

    class << self
      def extend_object(base)
        return if base.is_a?(self)

        super

        base.configure(:sauce_ondemand_username, :sauce_ondemand_access_key) do |user, key, options|
          options[:url] = URI.parse(URL)

          options[:url].user = user
          options[:url].password = key
        end

        base.configure(:platform) do |platform, options|
          options[:desired_capabilities].platform = platform
        end

        base.configure(:version) do |version, options|
          options[:desired_capabilities].version = version
        end
      end
    end

    # Submits status and Jenkins build info to Sauce Labs.
    #
    def teardown(env, status)
      each do |browser|
        sid = browser.driver.session_id
        url = browser.driver.send(:bridge).http.send(:server_url)
        username = url.user
        key = url.password

        RestClient::Request.execute(
          method: :put,
          url: "https://saucelabs.com/rest/v1/#{username}/jobs/#{sid}",
          user: username,
          password: key,
          headers: { content_type: 'application/json' },
          payload: {
            public: true,
            passed: status == :passed,
            build: env.lookup(:build_number, default: nil)
          }.to_json
        )

        Cucumber::Formatter::Sauce.current_session_id = sid
      end
    end

    protected

    def finalize_options!(options)
      case @browser_name
      when :firefox
        options[:desired_capabilities][:firefox_profile] = options.delete(:profile)
      when :chrome
        options[:desired_capabilities]['chromeOptions'] ||= {}
        options[:desired_capabilities]['chromeOptions']['prefs'] = options.delete(:prefs)
        options[:desired_capabilities]['chromeOptions']['args'] = options.delete(:args)
      end
    end

    def new_browser(options)
      Watir::Browser.new(:remote, options).tap do |browser|
        browser.driver.file_detector = lambda do |args|
          # args => ["/path/to/file"]
          str = args.first.to_s
          str if File.exist?(str)
        end
      end
    end
  end
end
