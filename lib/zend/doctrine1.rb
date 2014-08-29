namespace :zend do
  namespace :doctrine1 do
    namespace :migrations do
      desc "Executes a migration to a specified version or the latest available version"
      task :migrate, :roles => :app, :only => { :primary => true }, :except => { :no_release => true } do
        
        on_rollback {
          if !interactive_mode || Capistrano::CLI.ui.agree("Do you really want to migrate #{application_env}'s database back to version #{currentVersion}? (y/N)")
            run "#{try_sudo} sh -c 'cd #{latest_release} && APPLICATION_ENV=#{application_env}  #{php_bin} #{zend_console} doctrine:migrations:migrate #{currentVersion} #{console_options} --no-interaction#{doctrine_em_flag}'", :once => true
          end
        }

        if !interactive_mode || Capistrano::CLI.ui.agree("Do you really want to migrate #{application_env}'s database? (y/N)")
          run "#{try_sudo} sh -c ' cd #{latest_release} && APPLICATION_ENV=#{application_env}  #{php_bin} #{zend_console} migrate #{console_options}'", :once => true
        end
      end
    end
  end
end
