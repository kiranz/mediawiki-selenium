require "watir-webdriver"

module MediawikiSelenium
  module BrowserFactory
    class Base
      attr_reader :type

      class << self
        def bind(name, &blk)
          raise ArgumentError, "no block given" unless block_given?

          default_bindings[name] ||= []
          default_bindings[name] << blk
        end

        def bindings
          if superclass <= Base
            default_bindings.merge(superclass.bindings) { |key, old, new| old + new }
          else
            default_bindings
          end
        end

        def default_bindings
          @default_bindings ||= {}
        end
      end

      bind(:browser_timeout) { |value, options| options[:http_client].timeout = value.to_i }

      def initialize(type)
        @type = type
        @bindings = {}
        @browser_cache = {}
      end

      def bind(name, &blk)
        @bindings[name] ||= []
        @bindings[name] << (blk || proc {})
      end

      def bindings
        self.class.bindings.merge(@bindings) { |key, old, new| old + new }
      end

      def browser_for(env)
        config = env.lookup_all(bindings.keys)
        @browser_cache[config] ||= Watir::Browser.new(type, browser_options(config))
      end

      def browser_options(config)
        options = default_browser_options.tap do |watir_options|
          bindings.each do |(name, bindings_for_option)|
            bindings_for_option.each do |binding|
              value = config[name]
              binding.call(value, watir_options) unless value.nil? || value.to_s.empty?
            end
          end
        end

        finalize_options!(options)

        options
      end

      protected

      def desired_capabilities
        Selenium::WebDriver::Remote::Capabilities.send(type)
      end

      def finalize_options!(options)
      end

      def http_client
        Selenium::WebDriver::Remote::Http::Default.new
      end

      private

      def default_browser_options
        { http_client: http_client, desired_capabilities: desired_capabilities }
      end
    end
  end
end
