Before('@custom-browser') do |scenario|
  @scenario = scenario
end

AfterConfiguration do |config|
  # Install a formatter that can be used to show feature-related warnings
  pretty_format, io = config.formats.find { |(format, _io)| format == 'pretty' }
  config.formats << ['MediawikiSelenium::WarningsFormatter', io] if pretty_format

  # Set up Raita logging if RAITA_DB_URL is set. Include any useful
  # environment variables that Jenkins would have set.
  env = MediawikiSelenium::Environment.load_default
  raita_url = env.lookup(:raita_url, default: nil)

  if raita_url
    raita_build = MediawikiSelenium::Raita.build_from(env)
    config.formats << ['MediawikiSelenium::Raita::Logger', { url: raita_url, build: raita_build }]
  end

  # Initiate headless mode
  if ENV['HEADLESS'] == 'true' && ENV['BROWSER'] != 'phantomjs'
    require 'headless'

    headless_options = {}.tap do |options|
      options[:display] = ENV['HEADLESS_DISPLAY'] if ENV.include?('HEADLESS_DISPLAY')
      options[:reuse] = false if ENV['HEADLESS_REUSE'] == 'false'
      options[:destroy_at_exit] = false if ENV['HEADLESS_DESTROY_AT_EXIT'] == 'false'
    end

    headless = Headless.new(headless_options)
    headless.start
  end
end

# Enforce a dependency check for all scenarios tagged with @extension- tags
Before do |scenario|
  # Backgrounds themselves don't have tags, so get them from the feature
  if scenario.is_a?(Cucumber::Ast::Background)
    tag_source = scenario.feature
  else
    tag_source = scenario
  end

  tags = tag_source.source_tag_names
  dependencies = tags.map { |tag| tag.match(/^@extension-(.+)$/) { |m| m[1].downcase } }.compact

  unless dependencies.empty?
    extensions = api.meta(:siteinfo, siprop: 'extensions').data['extensions']
    extensions = extensions.map { |ext| ext['name'] }.compact.map(&:downcase)
    missing = dependencies - extensions

    if missing.any?
      scenario.skip_invoke!

      if scenario.feature.respond_to?(:mw_warn)
        warning = "Skipped feature due to missing wiki extensions: #{missing.join(", ")}"
        scenario.feature.mw_warn(warning, 'missing wiki extensions')
      end
    end
  end
end

Before do |scenario|
  # Create a unique random string for this scenario
  @random_string = Random.new.rand.to_s

  # Annotate sessions with the scenario name and Jenkins build info
  browser_factory.configure do |options|
    options[:desired_capabilities][:name] = test_name(scenario)
  end

  browser_factory.configure(:job_name) do |job, options|
    options[:desired_capabilities][:name] += " #{job}"
  end

  browser_factory.configure(:build_number) do |build, options|
    options[:desired_capabilities][:name] += "##{build}"
  end
end

After do |scenario|
  if scenario.respond_to?(:status)
    require 'fileutils'

    teardown(scenario.status) do |browser|
      # Embed remote session URLs
      if remote? && browser.driver.respond_to?(:session_id)
        embed("http://saucelabs.com/jobs/#{browser.driver.session_id}", 'text/url')
      end

      # Take screenshots
      if scenario.failed? && lookup(:screenshot_failures, default: false) == 'true'
        screen_dir = lookup(:screenshot_failures_path, default: 'screenshots')
        FileUtils.mkdir_p screen_dir
        name = test_name(scenario).gsub(/ /, '_')
        path = "#{screen_dir}/#{name}.png"
        browser.screenshot.save path
        embed path, 'image/png'
      end

    end
  else
    teardown
  end
end
