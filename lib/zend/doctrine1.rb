namespace :zend do
  namespace :doctrine1 do
    namespace :migrations do
      desc "Executes a migration to a specified version or the latest available version"
      task :migrate, :roles => :app, :only => { :primary => true }, :except => { :no_release => true } do
        
        env       = fetch(:deploy_env, "remote")
        filename  = "#{application}.#{env}_dump.#{release_name}.sql.gz"
        file      = "#{backup_path}/#{filename}"
        
        on_rollback {
          if !interactive_mode || Capistrano::CLI.ui.agree("Restore the #{application_env} database from dump file: #{file}? (y/N)")
            upload(file, "#{remote_tmp_dir}/#{filename}", :via => :scp)
            data = capture("#{try_sudo} gunzip -dc < #{remote_tmp_dir}/#{filename} | mysql -u#{config[:username]} --host='#{config[:hostname]}' --password='#{config[:password]}' #{config[:database]}")
            puts data
      
            run "#{try_sudo} rm -f #{remote_tmp_dir}/#{filename}"
          end
        }

        if !interactive_mode || Capistrano::CLI.ui.agree("Do you really want to migrate #{application_env}'s database? (y/N)")
          run "#{try_sudo} sh -c ' cd #{latest_release} && APPLICATION_ENV=#{application_env}  #{php_bin} #{doctrine_console} migrate #{console_options}'", :once => true
        end
      end
    end
  end
end
