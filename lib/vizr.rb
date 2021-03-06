#!/usr/bin/env ruby -W0

me = if File.symlink?(__FILE__)
  File.readlink(__FILE__)
else
  __FILE__
end

VIZR_ROOT =  File.expand_path("..", File.dirname(me))
WORKING_DIR = Dir.pwd

require 'rubygems'
require 'bundler/setup'
require 'grit'
require 'rake'
require 'optparse'
require 'yaml'
require 'handlebars'
require 'listen'
require 'pathname'
require 'erb'
require 'open3'

#disable fileutils verbosity
verbose(false)

load File.join(VIZR_ROOT, 'tasks/build.rb')
load File.join(VIZR_ROOT, 'tasks/dist.rb')
load File.join(VIZR_ROOT, 'tasks/upload.rb')
load File.join(VIZR_ROOT, 'tasks/packages.rb')

EMPTY_PROJECT_PATH = "./projects"
DOT_FILE = ".vizr"
LOCK_FILE = ".vizr-lock"
USER_FILE = "~/.vizrrc"

DEV_PATH = "./dev"
BUILD_PATH = "./build"
TMP_PATH = "./tmpbuild"

COMMANDS = {}

COMMANDS[:create] = Proc.new do |args|
  options = {
    :type => :requirejs
  }
  parser = OptionParser.new do |opts|
    opts.banner = "usage: vizr create [args] <projectpath>"

    opts.on("-t", "--type TYPE", [:basic, :requirejs, :package], "Predefined project type (defaults to #{options[:type]})") do |type|
      options[:type] = type.to_sym
    end

    add_update_help_opts(opts, options)
  end

  parser.parse!(args)
  setup_env(:create, args, :check_if_project => false) do |target, env|
    src = File.join(File.expand_path(File.join(EMPTY_PROJECT_PATH, options[:type].to_s), VIZR_ROOT), ".")
    cp_r(src, target, {})
    touch(File.join(target, DOT_FILE))
    sh "echo \"#{LOCK_FILE}\" >> \"#{File.join(target, ".gitignore")}\""
  end
end

COMMANDS[:build] = Proc.new do |args|
  options = {
    :minify => true,
    :jslint => false,
    :merge => true,
    :watch => false,
    :server => false,
    :server_port => 8000
  }
  parser = OptionParser.new do |opts|
    opts.banner = "usage: vizr build [args] <projectpath>"

    opts.on("--[no-]minify", "Minify assets if available (#{options[:minify] ? "enabled" : "disabled"} by default)") do |minify|
      options[:minify] = minify
    end

    opts.on("--[no-]jslint", "Lint check JavaScript (#{options[:jslint] ? "enabled" : "disabled"} by default)") do |jslint|
      options[:jslint] = jslint
    end

    opts.on("--[no-]merge", "Merge JS and CSS files (#{options[:merge] ? "enabled" : "disabled"} by default)") do |merge|
      options[:merge] = merge
    end

    opts.on("--dev", "Development build (no minify, lint, or merge)") do
      options[:minify] = false
      options[:jslint] = false
      options[:merge] = false
    end

    opts.on("--watch", "Rebuild project on file changes") do
      options[:watch] = true
    end

    opts.on("--serve", "Enable HTTP server on build directory if watching for changes") do
      options[:server] = true
    end

    opts.on("--port PORT", Integer, "Enable HTTP server on build directory (8000 by default)") do |port|
      options[:server_port] = port
    end

    add_update_help_opts(opts, options)
  end

  parser.parse!(args)
  setup_env(:build, args, options) do |target, env|
    Rake::Task["build"].invoke(target, options)
  end
end

COMMANDS[:dist] = Proc.new do |args|
  options = {
    :filename => "dist.zip"
  }

  parser = OptionParser.new do |opts|
    opts.banner = "usage: vizr dist [args] <projectpath>"
    options[:name] = "dist.zip"
    opts.on("-n", "--filename [NAME]", "File name of zip (default: dist.zip)") do |filename|
      options[:filename] = filename
    end

    add_update_help_opts(opts, options)
  end

  parser.parse!(args)
  setup_env(:dist, args) do |target, env|
    Rake::Task["package"].invoke(target, options)
  end
end

COMMANDS[:pull] = Proc.new do |args|
  pull = true
  parser = OptionParser.new do |opts|
    opts.banner = "Update vizr builder to new version\nusage: vizr pull [args]"

    opts.on_tail("-h", "--help", "Show this message") do
      pull = false
      puts opts
      exit
    end
  end

  parser.parse!(args)
  if pull

    cd(VIZR_ROOT)
    begin
      if out_of_date?
        puts "git out of date...updating"
        sh "git pull"
      else
        puts "git up to date"
      end

      puts "checking dependencies"
      sh "bundle install"

    rescue Grit::Git::GitTimeout => e
      puts "Can't connect to remote branch. Try again later"
    rescue => e
      # another assumption
      puts "Can't connect to remote branch. Try again later"
    end
  else
    puts parser
  end
end

COMMANDS[:upload] = Proc.new do |args|
  options = {
    :filename => "dist.zip",
    :version_files => true
  }

  parser = OptionParser.new do |opts|
    opts.banner = "usage: vizr upload [args] <projectpath>"
    opts.on("-n", "--filename [NAME]", "File name of zip (default: dist.zip)") do |filename|
      options[:filename] = filename
    end

    opts.on("--[no-]version", "Version files (versioning allows web browsers to cache content)") do |version|
      options[:version_files] = version
    end

    add_update_help_opts(opts, options)
  end

  parser.parse!(args)
  setup_env(:upload, args) do |target, env|
    options = env.update(options)
    Rake::Task["upload"].invoke(target, options)
  end
end

COMMANDS[:install] = Proc.new do |args|
  options = {}

  parser = OptionParser.new do |opts|
    opts.banner = "usage: vizr install [args] <projectpath> <package>"

    add_update_help_opts(opts, options)
  end

  parser.parse!(args)
  setup_env(:install, args) do |target, env|
    if args[1]
      options[:package] = args[1]

      Rake::Task["install"].invoke(target, options)
    else
      help(:install)
    end
  end
end

COMMANDS[:remove] = Proc.new do |args|
  options = {}

  parser = OptionParser.new do |opts|
    opts.banner = "usage: vizr remove [args] <projectpath> <package>"

    add_update_help_opts(opts, options)
  end

  parser.parse!(args)
  setup_env(:remove, args) do |target, env|
    if args[1]
      options[:package] = args[1]

      Rake::Task["remove"].invoke(target, options)
    else
      help(:remove)
    end
  end
end

COMMANDS[:help] = Proc.new do |args|
  help(args[0])
end

def add_update_help_opts(opts, options)
  opts.on("--skip-update-check", "Skip check for vizr updates") do
    options[:check_for_updates] = false
  end

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end

def help(command = nil)
  # handles case when someone enters in "vizr help <command>"
  if command && COMMANDS[command.to_sym]
    parse_args(command.to_sym, ["-h"])
    exit
  end

  # max spaces to show between command and description
  spaces = 10

  # output info
  puts "usage: vizr <command> [<args>]\n\n"
  puts "vizr commands are:"
  [
    ["build", "build a vizr project"],
    ["create", "create a new vizr project"],
    ["install", "install a package"],
    ["remove", "remove a package"],
    ["dist", "zip up the contents of a project's build folder"],
    ["help", "this information"],
    ["pull", "update vizr builder to newest version"],
    ["upload", "upload a project zip to a server"]
  ].each do |cmd|
    puts "   #{cmd[0]}#{" " * (spaces - cmd[0].length)}#{cmd[1]}"
  end
  puts "\nSee 'vizr help <command>' for more information on a specific command"
end

def setup_env(command, args, options = {}, &block)
  options = {
    :check_if_project => true,
    :check_for_updates => true
  }.update(options)

  check_for_updates() if options[:check_for_updates]

  if args[0]
    target = File.expand_path(args[0], WORKING_DIR)

    user_file = check_for_user_file()
    dot_file = check_for_dot_file(target) if options[:check_if_project]

    env = {}
    env.merge!(YAML.load_file(user_file)) if user_file
    if user_file
      prefs = YAML.load_file(user_file)

      case prefs
        when Hash
          env.merge!(prefs)
      end
    end
    if dot_file
      prefs = YAML.load_file(dot_file)

      case prefs
        when Hash
          env.merge!(prefs)
      end
    end

    if (!options[:check_if_project] || dot_file) && (!options[:check_if_project] || check_lock(target))
      block.call(target, env)
    end
  else
    help(command)
  end
end

def check_for_dot_file(target)
  dot_file = [DOT_FILE, ".vizer"].find do |file|
    File.exists?(File.join(target, file))
  end

  if dot_file
    File.join(target, dot_file)
  else
    message(:not_a_project, {
      :target => target
    })
    nil
  end
end

def check_for_user_file
  user_file = File.expand_path(USER_FILE)
  if File.exists?(user_file)
    user_file
  else
    nil
  end
end

def check_lock(target)
  ok = true
  found = false
  lock_path = File.join(target, LOCK_FILE)
  lock_paths_to_check = [LOCK_FILE, ".vizer-lock"]
  content = nil
  begin
    lock_paths_to_check.count do |path|
      path = File.join(target, path)
      found = File.exists?(path)
      if found
        content = File.read(path)
        ok = (content.strip == target.strip)
      end

      break if found && ok
    end

    unless found
      raise "Couldn't find file"
    end
  rescue
    # create lock file
    sh %{echo "#{target}" > "#{lock_path}"}

    # make sure lock file doesn't get checked in
    ignore = File.join(target, ".gitignore")
    sh %{grep #{LOCK_FILE} #{ignore} > /dev/null} do |ok, res|
      if not ok
        sh %{echo "#{LOCK_FILE}" >> "#{ignore}"}
      end
    end
  end

  if not ok
    message(:locked, {
      :copied_from => (content || "<empty file>").strip,
      :target => target.strip,
      :lock_file => LOCK_FILE
    })
    exit
  end

  ok
end

def check_for_updates
  path = File.join(VIZR_ROOT, ".last_update_check")

  make_check = true
  if File.exists?(path)
    begin
      now = Time.now.to_i
      last_check = File.read(path).strip.to_i
      elasped_time = now - last_check

      # check every 30min
      make_check = elasped_time > 30 * 60 # 30m * 60s = 30 minutes in seconds
    rescue
    end
  end

  if make_check
    puts "checking for updates..."
    begin
      if out_of_date?

        repo = Grit::Repo.new(VIZR_ROOT)
        branch = repo.head.name
        local_rev = repo.git.rev_list({ :max_count => 1 }, branch)
        remote_rev = repo.git.rev_list({ :max_count => 1 }, "origin/#{branch}")
        commits = repo.commits_between(local_rev, remote_rev).map{|commit| "#{commit.short_message} (#{commit.author})" }

        message(:out_of_date, {
          :commits => commits
        })
      else
        puts "already up to date"
        File.open(path, "w") do |file|
          file.write(Time.now.to_i.to_s)
        end
      end
    rescue Grit::Git::GitTimeout => e
      puts "Can't connect to remote branch. Try again later"
    end

  end
end

def out_of_date?
  repo = Grit::Repo.new(VIZR_ROOT)

  branch = repo.head.name
  repo.remote_fetch('origin')
  local_rev = repo.git.rev_list({ :max_count => 1 }, branch)
  remote_rev = repo.git.rev_list({ :max_count => 1 }, "origin/#{branch}")

  # making some assumptions here
  local_rev != remote_rev
end

def message(name, context = {})
  content = ""
  path = File.expand_path("messages/#{name.to_s}.hbs", VIZR_ROOT)
  File.open(path, "r") do |file|
    content = file.read
  end

  handlebars = Handlebars::Context.new
  template = handlebars.compile(content)
  puts ""
  puts template.call(context)
  puts ""
end

def parse_args(command_name, args)
  command_name = command_name || :help
  args = args || []
  command = COMMANDS[command_name] || COMMANDS[:help]

  command.call(args)
end

cmd = ARGV[0].to_sym rescue nil
parse_args(cmd, ARGV[1..-1])
