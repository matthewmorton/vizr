require 'rest_client'
require 'json'

task :upload, :target, :options do |t, args|

  target = args[:target]
  options = args[:options]

  # Prevent an upload from happening until the target repo is in a clean state
  dirty_git = !(system "git diff-index --quiet HEAD #{target}")
  if dirty_git
    abort("Aborted. Uncommitted changes in target repo.")
  end

  # Don't let an upload happen until a non-dev build is completed and a vizr dist is done.
  COMMANDS[:build].call([target]) # Use default options for build
  COMMANDS[:dist].call([target]) # Use default options for dist

  api_key = options['api_key']
  endpoint = options['upload']['endpoint']
  dist_path = File.join(target, options[:filename])

  params = {
    :api_key => api_key,
    :data => File.new(dist_path),
    :accept => :json
  }
  params[:version_files] = "1" if options[:version_files]

  if api_key && endpoint
    $stdout.sync = true
    print "uploading..."

    response = nil

    Thread.new do 
      response = RestClient.put(endpoint, params)
    end

    while !response
      print "."
      sleep(1)
    end
    puts ""

    project = JSON.parse(response.to_s)

    message(:upload_successful, {
      :success => project['success'],
      :uploaded => project['changes'][0]['uploaded'].empty? ? nil : project['changes'][0]['uploaded'].map { |o| o['key'] },
      :removed => project['changes'][0]['removed'].empty? ? nil : project['changes'][0]['removed'].map { |o| o['key'] },
      :files => project['files'],
      :base_url => project['base_url']
    })
  end
end
