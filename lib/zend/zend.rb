namespace :zend do
  desc "Runs custom zend command"
  task :default, :roles => :app, :except => { :no_release => true } do
    prompt_with_default(:task_arguments, "cache:clear")

    stream "#{try_sudo} sh -c 'cd #{latest_release} && #{php_bin} #{zend_console} #{task_arguments} #{console_options}'"
  end


  namespace :logs do
    [:tail, :tail_dev].each do |action|
      lines = ENV['lines'].nil? ? '50' : ENV['lines']
      log   = action.to_s == 'tail' ? 'prod.log' : 'dev.log'
      desc "Tail #{log}"
      task action, :roles => :app, :except => { :no_release => true } do
        log   = action.to_s == 'tail' ? "#{zend_env_prod}.log" : "#{zend_env_local}.log"
        run "#{try_sudo} tail -n #{lines} -f #{shared_path}/#{log_path}/#{log}" do |channel, stream, data|
          trap("INT") { puts 'Interupted'; exit 0; }
          puts
          puts "#{channel[:host]}: #{data}"
          break if stream == :err
        end
      end
    end
  end


  namespace :bootstrap do
    desc "Runs the bin/build_bootstrap script"
    task :build, :roles => :app, :except => { :no_release => true } do
      # todo
      capifony_puts_ok
    end
  end

  namespace :composer do
    desc "Gets composer and installs it"
    task :get, :roles => :app, :except => { :no_release => true } do
      install_options = ''
      unless composer_version.empty?
        install_options += " -- --version=#{composer_version}"
      end

      if use_composer_tmp
        # Because we always install to temp location we assume that we download composer every time.
        logger.debug "Downloading composer to #{$temp_destination}"
        capifony_pretty_print "--> Downloading Composer to temp location"
        run_locally "cd #{$temp_destination} && curl -s http://getcomposer.org/installer | #{php_bin}#{install_options}"
      else
        if !remote_file_exists?("#{latest_release}/composer.phar")
          capifony_pretty_print "--> Downloading Composer"

          run "#{try_sudo} sh -c 'cd #{latest_release} && curl -s http://getcomposer.org/installer | #{php_bin}#{install_options}'"
        else
          capifony_pretty_print "--> Updating Composer"

          run "#{try_sudo} sh -c 'cd #{latest_release} && #{php_bin} composer.phar self-update #{composer_version}'"
        end
      end
      capifony_puts_ok
    end

    desc "Updates composer"

    desc "Runs composer to install vendors from composer.lock file"
    task :install, :roles => :app, :except => { :no_release => true } do

      if !composer_bin
        zend.composer.get
        set :composer_bin, "#{php_bin} composer.phar"
      end

      options = "#{composer_options}"
      if !interactive_mode
        options += " --no-interaction"
      end

      if use_composer_tmp
        logger.debug "Installing composer dependencies to #{$temp_destination}"
        capifony_pretty_print "--> Installing Composer dependencies in temp location"
        run_locally "cd #{$temp_destination} && APPLICATION_ENV=#{zend_env_prod} #{composer_bin} install #{options}"
        capifony_puts_ok
      else
        capifony_pretty_print "--> Installing Composer dependencies"
        run "#{try_sudo} sh -c 'cd #{latest_release} && APPLICATION_ENV=#{zend_env_prod} #{composer_bin} install #{options}'"
        capifony_puts_ok
      end
    end

    desc "Runs composer to update vendors, and composer.lock file"
    task :update, :roles => :app, :except => { :no_release => true } do
      if !composer_bin
        zend.composer.get
        set :composer_bin, "#{php_bin} composer.phar"
      end

      options = "#{composer_options}"
      if !interactive_mode
        options += " --no-interaction"
      end

      capifony_pretty_print "--> Updating Composer dependencies"
      run "#{try_sudo} sh -c 'cd #{latest_release} && APPLICATION_ENV=#{zend_env_prod} #{composer_bin} update #{options}'"
      capifony_puts_ok
    end

    desc "Dumps an optimized autoloader"
    task :dump_autoload, :roles => :app, :except => { :no_release => true } do
      if !composer_bin
        zend.composer.get
        set :composer_bin, "#{php_bin} composer.phar"
      end

      capifony_pretty_print "--> Dumping an optimized autoloader"
      run "#{try_sudo} sh -c 'cd #{latest_release} && #{composer_bin} dump-autoload #{composer_dump_autoload_options}'"
      capifony_puts_ok
    end

    task :copy_vendors, :except => { :no_release => true } do
      capifony_pretty_print "--> Copying vendors from previous release"

      run "vendorDir=#{current_path}/vendor; if [ -d $vendorDir ] || [ -h $vendorDir ]; then cp -a $vendorDir #{latest_release}; fi;"
      capifony_puts_ok
    end

    # Install composer to temp directory.
    # Not sure if this is required yet.
    desc "Dumps an optimized autoloader"
    task :dump_autoload_temp, :roles => :app, :except => { :no_release => true } do
      if !composer_bin
        zend.composer.get_temp
        set :composer_bin, "#{php_bin} composer.phar"
      end

      logger.debug "Dumping an optimised autoloader to #{$temp_destination}"
      capifony_pretty_print "--> Dumping an optimized autoloader to temp location"
      run_locally cd "#{$temp_destination} && #{composer_bin} dump-autoload --optimize"
      capifony_puts_ok
    end

  end
end
