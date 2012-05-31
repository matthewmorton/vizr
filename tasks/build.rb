NODE_VERSION = "0.6.18"
NODE_VERSION_FILTER = /v0\.6.*/

JS_DIR = "js"
CONFIG_DIR = "config"
VENDOR_DIR = "vendor"

JSHINTRC_FILE = ".jshintrc"
REQUIRE_JS_BUILD_FILE = "require.build.js"

task :build, :target, :options do |t, args|
  target = args[:target]
  options = args[:options]
  dev = File.expand_path(DEV_PATH, target)
  tmp = File.expand_path(TMP_PATH, target)
  build = File.expand_path(BUILD_PATH, target)

  if options[:watch]

    puts "\nWatching project for changes..."

    last_change_time = Time.now.to_f

    rebuild = lambda { |base, relative|
      puts "Updated #{File.join(base, relative)}"

      time_since_build = Time.now.to_f - last_change_time

      puts "#{time_since_build} seconds since last build"

      # only run tasks if we have not run the tasks in the last second
      # this tries to prevent multiple builds when > 1 file updates simultaneously
      if time_since_build >= 1.0
        watched_build(target, options)
        last_change_time = Time.now.to_f
      else
        puts "Last build less than 1 seconds ago, skipping"
      end
    }

    # Run the first build
    watched_build(target, options)

    # Watch for changes
    FSSM.monitor(target, ["dev/**/*", "env.yaml"], :directories => true) do
      update {|base, relative| rebuild.call(base, relative)}
      create {|base, relative| rebuild.call(base, relative)}
      delete {|base, relative| rebuild.call(base, relative)}
    end

  else # single build / no watching

    single_build(target, options)

  end
end

def watched_build(target, options)
  [ :create_working_directory,
    :process_files,
    :create_build_directory,
    :move_to_build,
    :clean_up
  ].each do |task|
    Rake::Task[task].reenable
    begin
      Rake::Task[task].invoke(target, options)
    rescue
      puts "ERROR: Build failed to complete, continuing to watch for changes"
      break
    end
  end
end

def single_build(target, options)
  [ :create_working_directory,
    :process_files,
    :create_build_directory,
    :move_to_build,
    :clean_up
  ].each do |task|
    Rake::Task[task].invoke(target, options)
  end
end

task :create_working_directory, :target do |t, args|
  target = args[:target]
  dev = File.expand_path(DEV_PATH, target)
  tmp = File.expand_path(TMP_PATH, target)
  build = File.expand_path(BUILD_PATH, target)

  rm_rf(tmp)
  cp_r(dev, tmp)
end

task :process_files, :target, :options do |t, args|
  target = args[:target]
  options = args[:options]
  minify = options[:minify]
  jslint = options[:jslint]
  merge = options[:merge]
  jopts = ''

  dev = File.expand_path(DEV_PATH, target)
  tmp = File.expand_path(TMP_PATH, target)
  build = File.expand_path(BUILD_PATH, target)

  # Check if project is jshint-enabled
  found_jshint_file = File.exists?(File.join(target, JSHINTRC_FILE))

  # If .jshintrc, use jshint and uglify, else use jslint and yui via juicer
  run_jshint = jslint && found_jshint_file
  run_jslint = jslint && !found_jshint_file
  run_uglify_js = minify && found_jshint_file
  run_yui_js = minify && !found_jshint_file

  # Check if project uses require.js
  requirejs_build_file = File.join(tmp, JS_DIR, CONFIG_DIR, REQUIRE_JS_BUILD_FILE)
  found_requirejs_build_file = File.exists?(requirejs_build_file)

  run_juicer_merge = !found_requirejs_build_file
  run_requirejs_optimizer = merge && found_requirejs_build_file

  if run_jshint
    setup_jshint

    puts "Running jshint..."
    sh "(cd #{tmp}; jshint .)"
  end

  if !run_yui_js
    jopts << ' -m none'
  end

  if !run_jslint
    jopts << ' -s'
  end

  if File.exist?(File.join(tmp, "css"))
    if run_juicer_merge
      puts "Running juicer on CSS..."
      Dir.glob(File.join(tmp, "css", "*.css")) do |item|
        sh "juicer merge -i #{jopts} #{item}"
        mv(item.gsub('.css', '.min.css'), item, :force => true)
      end
    end
  end

  if File.exist?(File.join(tmp, "js"))
    if run_juicer_merge
      puts "Running juicer on JS..."
      Dir.glob(File.join(tmp, "js", "*.js")) do |item|
        sh "juicer merge -i #{jopts} #{item}"
        mv(item.gsub('.js', '.min.js'), item, :force => true)
      end
    end

    if run_requirejs_optimizer
      setup_requirejs

      puts "Running RequireJS optimizer on JS & CSS..."
      sh "r.js -o #{requirejs_build_file}"
    end

    if run_uglify_js
      setup_uglify_js

      Dir.glob(File.join(tmp, "js", "*.js")) do |item|
        puts "Running uglify-js on #{item}..."
        sh "uglifyjs #{item} > #{item}.min"
        mv(item.gsub('.js', '.js.min'), item, :force => true)
      end
    end
  end

  puts "Applying env.yaml settings..."
  Dir[File.join(tmp, "*.hbs")].each do |hbs|
    sh "ruby #{File.join(VIZR_ROOT, "lib", "parse_hbs.rb")} \"#{hbs}\" #{File.join(target, "env.yaml")} > #{File.join(tmp, File.basename(hbs, ".hbs"))}"
  end
end

def setup_requirejs
  if !node?
    node_missing
  end

  if !which?("r.js")
    sh "npm install -g requirejs@2.0.0"
  end
end

def setup_uglify_js
  if !node?
    node_missing
  end

  if !which?("uglifyjs")
    sh "npm install -g uglify-js@1.2.6"
  end
end

def setup_jshint
  if !node?
    node_missing
  end

  if !which?("jshint")
    sh "npm install -g jshint@0.7.1"
  end
end

def node?
  # First test if node exists at all
  if !which?("node")
    return false
  end

  # Is it an acceptable version?
  version = ""
  IO.popen("node --version") { |io|
    version = io.read
  }

  if !(version =~ NODE_VERSION_FILTER)
    return false
  end

  return true
end

def which?(program)
  IO.popen("which #{program}") { |io|
    io.read
  }

  if !$?.exitstatus.zero?
    return false
  end

  return true
end

def node_missing
  message("nodejs_dependency", {
    :node_version => NODE_VERSION
  })
  exit
end

task :create_build_directory, :target do |t, args|
  target = args[:target]
  dev = File.expand_path(DEV_PATH, target)
  tmp = File.expand_path(TMP_PATH, target)
  build = File.expand_path(BUILD_PATH, target)

  # remove only build folder contents, not the folder
  # prevents weird file descriptor issue if directly serving directory
  rm_rf(Dir[File.join(build, "*")])

  # create directory if it doesn't exist
  mkdir_p(build)
end

task :move_to_build, :target, :options do |t, args|
  target = args[:target]
  options = args[:options]

  dev = File.expand_path(DEV_PATH, target)
  tmp = File.expand_path(TMP_PATH, target)
  build = File.expand_path(BUILD_PATH, target)

  ["css", "js", "img", "fonts"].each do |folder|
    if File.exists?(File.join(tmp, folder))
      mkdir_p(File.join(build, folder))
      cp_r(File.join(tmp, folder), build)
    end
  end

  cp(Dir[File.join(tmp, "*.html")], build)
  cp(Dir[File.join(tmp, "*.manifest")], build)

  sh "ruby #{File.join(VIZR_ROOT, "lib", "cachepath.rb")} \"#{build}\" \"#{File.join(build, "**", "*")}\" > #{File.join(build, "js", "cachepath.js")}"
end

task :clean_up, :target do |t, args|
  target = args[:target]
  dev = File.expand_path(DEV_PATH, target)
  tmp = File.expand_path(TMP_PATH, target)
  build = File.expand_path(BUILD_PATH, target)

  rm_rf(tmp)
end
