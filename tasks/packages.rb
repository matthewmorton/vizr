task :install, :target, :options do |t, args|
  target = args[:target]
  options = args[:options]
  package = options[:package]

  target_segments = target.split("/")
  for removed_segs in 0..target_segments.length
    root_dir = File.join(target_segments[0...(target_segments.length - removed_segs)])
    if File.exists?(File.join(root_dir, ".git"))
      break
    end
  end

  package_repo = File.join(root_dir, "massrel-products", "packages")

  if root_dir.empty? || !File.exists?(package_repo)
    puts "ERROR: Couldn't find package repo. Are you inside the viz repo?"
    exit
  end

  package_path = File.join(package_repo, package, "dev")
  if !File.exists?(package_path)
    puts "ERROR: Package #{package} does not exist"
    exit
  end

  packages_dir = File.join(target, "dev", "packages")

  mkdir_p(packages_dir)
 
  begin
    File.symlink(package_path, File.join(packages_dir, package))
  rescue
    puts "ERROR: Couldn't install #{package}, may already be installed"
  end

  puts "Package #{package} installed"
end

task :remove, :target, :options do |t, args|
  target = args[:target]
  options = args[:options]
  package = options[:package]

  packages_dir = File.join(target, "dev", "packages")
  package_link = File.join(packages_dir, package)

  if !File.exists?(package_link)
    puts "ERROR: Package #{package} is not installed"
    exit
  end

  rm_f(package_link)
end
