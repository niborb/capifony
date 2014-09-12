require 'fileutils'
require 'zlib'

namespace :database do
  
  namespace :remote do
    desc "Migrates a remote database"
    task :migrate, :roles => :db, :only => { :primary => true } do
      database.remote.dump
      
      transaction do
        if model_manager == "doctrine2"
          zend.doctrine2.migrations.migrate
        elsif model_manager == "doctrine1"
          zend.doctrine1.migrations.migrate
        end
      end
      
      local.cleanup
    end
    
    desc "Restores the remote database from the latest dump"
    task :restore, :roles => :db, :only => { :primary => true } do
      config      = load_database_config
      filename    = "#{application}.remote.#{config[:database]}.#{application_env}.latest.sql.gz"
      local_file  = "#{backup_path}/#{filename}"
      remote_file = "#{remote_tmp_dir}/#{filename}"
      
      if !interactive_mode || Capistrano::CLI.ui.agree("Restore the remote #{application_env} database from dump file: #{local_file}? (y/N)")
        capifony_progress_start
        put(File.read(local_file), remote_file, :via => :scp) do |channel, name, sent, total|
          capifony_progress_update(sent, total)
        end
        
        data = capture("#{try_sudo} sh -c 'gunzip -dc < #{remote_file} | mysql --max_allowed_packet=64M -u#{config[:username]} --host=\"#{config[:hostname]}\" --password=\"#{config[:password]}\" #{config[:database]}'")
        puts data
  
        run "#{try_sudo} rm -f #{remote_file}"
      end
    end
    
    desc "Dumps remote database"
    task :dump, :roles => :db, :only => { :primary => true } do
      config      = load_database_config
      filename    = "#{application}.remote.#{config[:database]}.#{application_env}.#{release_name}.sql.gz"
      remote_file = "#{remote_tmp_dir}/#{filename}"
      
      data = capture("#{try_sudo} sh -c '#{remote_mysqldump_bin} --max_allowed_packet=64M -u#{config[:username]} --host=\"#{config[:hostname]}\" --password=\"#{config[:password]}\" #{config[:database]} | gzip -c > #{remote_file}'")
      puts data

      FileUtils.mkdir_p("#{backup_path}")

      capifony_progress_start
      get(remote_file, "#{backup_path}/#{filename}", :via => :scp) do |channel, name, sent, total|
        capifony_progress_update(sent, total)
      end

      begin
        FileUtils.ln_sf(filename, "#{backup_path}/#{application}.remote.#{config[:database]}.#{application_env}.latest.sql.gz")
      rescue Exception # fallback for file systems that don't support symlinks
        FileUtils.cp_r("#{backup_path}/#{filename}", "#{backup_path}/#{application}.remote.#{config[:database]}.#{application_env}.latest.sql.gz")
      end
      run "#{try_sudo} rm -f #{remote_file}"
    end
  
    desc "Dumps remote database, downloads it to local, and populates here"
    task :copy_to_local, :roles => :db, :only => { :primary => true } do
      database.remote.dump
      remote_config = load_database_config
      local_config  = load_database_config('development')
      filename    = "#{application}.remote.#{remote_config[:database]}.#{application_env}.latest.sql.gz"
      local_file  = "#{backup_path}/#{filename}"
        
      cmd = "gunzip -dc < #{local_file} | #{local_mysql_bin} -u#{local_config[:username]} --password=\"#{local_config[:password]}\" #{local_config[:database]}"
      p "executing command: #{cmd}"
      `#{cmd}`
    end
  end
    
  namespace :local do
    desc "Dumps local database"
    task :dump do
      config      = load_database_config('development')
      filename    = "#{application}.local.#{config[:database]}.#{application_env}.#{release_name}.sql.gz"
      local_file  = "#{backup_path}/#{filename}"
      
      FileUtils::mkdir_p("#{backup_path}")
      
      cmd = "#{local_mysqldump_bin} -S #{local_mysql_socket} -u#{config[:username]} --password='#{config[:password]}' #{config[:database]} | gzip -c > #{local_file}"
      p "executing command: #{cmd}"
      `#{cmd}`

      begin
        FileUtils.ln_sf(filename, "#{backup_path}/#{application}.local.#{config[:database]}.#{application_env}.latest.sql.gz")
      rescue Exception # fallback for file systems that don't support symlinks
        FileUtils.cp_r("#{backup_path}/#{filename}", "#{backup_path}/#{application}.local.#{config[:database]}.#{application_env}.latest.sql.gz")
      end
    end
    
    desc "Dumps local database, loads it to remote, and populates there"
    task :copy_to_remote, :roles => :db, :only => { :primary => true } do
      database.local.dump
      local_config = load_database_config('development')
      remote_config = load_database_config
      filename    = "#{application}.local.#{local_config[:database]}.#{application_env}.#{release_name}.sql.gz"
      local_file  = "#{backup_path}/#{filename}"
      remote_file = "#{remote_tmp_dir}/#{filename}"

      capifony_progress_start
      put(local_file, remote_file, :via => :scp) do |channel, name, sent, total|
        capifony_progress_update(sent, total)
      end

      data = capture("#{try_sudo} sh -c 'gunzip -dc < #{remote_file} | #{remote_mysql_bin} --max_allowed_packet=64M -u#{remote_config[:username]} --host=\"#{remote_config[:hostname]}\" --password=\"#{remote_config[:password]}\" #{remote_config[:database]}'")
      puts data

      run "#{try_sudo} rm -f #{remote_file}"
    end
    
    desc "Clean-up database dumps"
    task :cleanup, :roles => :db, :only => { :primary => true } do
      count = fetch(:keep_releases, 5).to_i
      
      config = load_database_config
      
      cmd = "ls -1dt #{application}.remote.#{config[:database]}.#{application_env}.2* | tail -n +#{count + 1} | xargs rm -rf"
      p "executing command: #{cmd}"
      `#{cmd}`
      
    end
    
  end
  
end
