# encoding: utf-8
require 'capistrano'
require 'capistrano/maintenance'
require 'colored'
require 'fileutils'
require 'inifile'
require 'yaml'
require 'zlib'
require 'ruby-progressbar'

module Capifony
  module Zend
    def self.load_into(configuration)
      configuration.load do

        load_paths.push File.expand_path('../', __FILE__)
        load 'capifony'
        load 'zend/zend'
        load 'zend/database'
        load 'zend/deploy'
        load 'zend/doctrine'
        load 'zend/web'
        load 'zend/shared'

        # Zend application path
        set :app_path,              "."

        # Zend web path
        set :web_path,              "public"

        # Zend console bin
        set :zend_console,       app_path + "/scripts/console.php"

        # Zend log path
        set :log_path,              app_path + "/var/logs"

        # Zend cache path
        set :cache_path,            app_path + "/var/cache"

        # Zend config file path
        set :app_config_path,       app_path + "/application/configs"

        # Zend config file (parameters.(ini|yml|etc...)
        set :app_config_file,       app_path + "/application/configs/application.dist.ini"

        # Whether to use composer to install vendors.
        # If set to false, it will use the bin/vendors script
        set :use_composer,          true

        # Whether to use composer to install vendors to a local temp directory.
        set :use_composer_tmp,     false

        # Path to composer binary
        # If set to false, Capifony will download/install composer
        set :composer_bin,          false

        # Release number to composer
        # If you would like to instead update to a specific release simply specify it (for example '1.0.0-alpha8')
        set :composer_version,      ""

        # Options to pass to composer when installing/updating
        set :composer_options,      "--no-dev --verbose --prefer-dist --optimize-autoloader --no-progress"

        # Options to pass to composer when dumping the autoloader (dump-autoloader)
        set :composer_dump_autoload_options, "--optimize"

        # Whether to update vendors using the configured dependency manager (composer or bin/vendors)
        set :update_vendors,        false

        # run bin/vendors script in mode (upgrade, install (faster if shared /vendor folder) or reinstall)
        set :vendors_mode,          "reinstall"

        # Copy vendors from previous release
        set :copy_vendors,          false

        # Whether to run cache warmup
        set :cache_warmup,          true

        # Files that need to remain the same between deploys
        set :shared_files,          false

        # Dirs that need to remain the same between deploys (shared dirs)
        set :shared_children,       [log_path, web_path + "/uploads"]

        # Dirs that need to be writable by the HTTP Server (i.e. cache, log dirs)
        set :writable_dirs,         [log_path, cache_path]

        # Name used by the Web Server (i.e. www-data for Apache)
        set :webserver_user,        "www-data"

        # Method used to set permissions (:chmod, :acl, or :chown)
        set :permission_method,     false

        # Execute set permissions
        set :use_set_permissions,   false

        # Model manager: (doctrine1, doctrine2)
        set :model_manager,         "doctrine"

        # Doctrine custom entity manager
        set :doctrine_em,           false

        # Database backup folder
        set :backup_path,           "backups"

        # If set to false, it will never ask for confirmations (migrations task for instance)
        # Use it carefully, really!
        set :interactive_mode,      true

        def load_database_config(data, env)
          read_parameters(data)['parameters']
        end


        def remote_file_exists?(full_path)
          'true' == capture("if [ -e #{full_path} ]; then echo 'true'; fi").strip
        end

        def remote_command_exists?(command)
          'true' == capture("if [ -x \"$(which #{command})\" ]; then echo 'true'; fi").strip
        end

        def console_options
          console_options = ''

          return console_options
        end

        STDOUT.sync
        $error = false
        $pretty_errors_defined = false

        # Be less verbose by default
        logger.level = Capistrano::Logger::IMPORTANT

        def capifony_pretty_print(msg)
          if logger.level == Capistrano::Logger::IMPORTANT
            pretty_errors

            msg = msg.slice(0, 57)
            msg << '.' * (60 - msg.size)
            print msg
          else
            puts msg.green
          end
        end

        def capifony_puts_ok
          if logger.level == Capistrano::Logger::IMPORTANT && !$error
            puts '✔'.green
          end

          $error = false
        end

        def pretty_errors
          if !$pretty_errors_defined
            $pretty_errors_defined = true

            class << $stderr
              @@firstLine = true
              alias _write write

              def write(s)
                if @@firstLine
                  _write('✘'.red << "\n")
                  @@firstLine = false
                end

                _write(s.red)
                $error = true
              end
            end
          end
        end

        $progress_bar = nil
        $download_msg_padding = nil

        def capifony_progress_start(msg = "--> Working")
          $download_msg_padding = '.' * (60 - msg.size)
          # Format is equivalent to "Title............82% ETA: 00:00:12"
          $progress_bar = ProgressBar.create(
            :title => msg,
            :format => "%t%B %p%% %e",
            :length => 60,
            :progress_mark => "."
          )
        end

        def capifony_progress_update(current, total)
          unless $progress_bar
            raise "Please create a progress bar using capifony_progress_start"
          end

          percent = (current.to_f / total.to_f * 100).floor

          if percent > 99
            green_tick = '✔'.green
            # Format is equivalent to "Title.............✔"
            $progress_bar.format("%t#{$download_msg_padding}#{green_tick}")
          end

          $progress_bar.progress = percent
        end

        [
          "zend:doctrine:cache:clear_metadata",
          "zend:doctrine:cache:clear_query",
          "zend:doctrine:cache:clear_result",
          "zend:doctrine:schema:create",
          "zend:doctrine:schema:drop",
          "zend:doctrine:schema:update",
          "zend:doctrine:load_fixtures",
          "zend:doctrine:migrations:migrate",
          "zend:doctrine:migrations:status",
        ].each do |action|
          before action do
            set :doctrine_em_flag, doctrine_em ? " --em=#{doctrine_em}" : ""
          end
        end

        ["zend:composer:install", "zend:composer:update", "zend:vendors:install", "zend:vendors:upgrade"].each do |action|
          before action do
            if copy_vendors
              zend.composer.copy_vendors
            end
          end
        end

        after "deploy:finalize_update" do
          if use_composer && !use_composer_tmp
            if update_vendors
              zend.composer.update
            else
              zend.composer.install
            end
          end

          if use_set_permissions
            # Set permissions after all cache files have been created
            zend.deploy.set_permissions
          end
        end

        before "deploy:update_code" do
          msg = "--> Updating code base with #{deploy_via} strategy"

          if logger.level == Capistrano::Logger::IMPORTANT
            pretty_errors
            puts msg
          else
            puts msg.green
          end
        end

        after "deploy:create_symlink" do
          puts "--> Successfully deployed!".green
        end

        # Recreate the autoload file after rolling back
        # https://github.com/everzet/capifony/issues/422
        after "deploy:rollback" do
            run "cd #{current_path} && #{composer_bin} dump-autoload #{composer_dump_autoload_options}"
        end

      end

    end
  end
end

if Capistrano::Configuration.instance
  Capifony::Zend.load_into(Capistrano::Configuration.instance)
end
