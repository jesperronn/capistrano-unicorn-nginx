require 'capistrano/dsl/nginx_paths'
require 'capistrano/unicorn_nginx/helpers'

include Capistrano::UnicornNginx::Helpers
include Capistrano::DSL::NginxPaths

namespace :load do
  task :defaults do
    set :templates_path, 'config/deploy/templates'
    set :nginx_config_name, -> { "#{fetch(:application)}_#{fetch(:stage)}" }
    set :nginx_pid, nginx_default_pid_file
    set :nginx_service_path, '/etc/init.d/nginx'
    # set :nginx_server_name # default set in the `nginx:defaults` task
    # ssl options
    set :nginx_location, '/etc/nginx'
    set :nginx_use_ssl, false
    set :nginx_use_spdy, false
    set :nginx_use_http2, false
    # if true, passes the SSL client certificate to the application server for consumption in Ruby code
    set :nginx_pass_ssl_client_cert, false
    set :nginx_ssl_cert, -> { nginx_default_ssl_cert_file_name }
    set :nginx_ssl_cert_key, -> { nginx_default_ssl_cert_key_file_name }
    set :nginx_ssl_cert_path, -> { nginx_default_ssl_cert_file_path }
    set :nginx_ssl_cert_key_path, -> { nginx_default_ssl_cert_key_file_path }
    set :nginx_upload_local_cert, true
    set :nginx_ssl_cert_local_path, -> { ask(:nginx_ssl_cert_local_path, 'Local path to ssl certificate: ') }
    set :nginx_ssl_cert_key_local_path, -> { ask(:nginx_ssl_cert_key_local_path, 'Local path to ssl certificate key: ') }
    set :nginx_fail_timeout, 0 # see http://nginx.org/en/docs/http/ngx_http_upstream_module.html#fail_timeout
    set :nginx_read_timeout, nil

    set :linked_dirs, fetch(:linked_dirs, []).push('log')
  end
end

namespace :nginx do

  task :defaults do
    on roles :web do
      set :nginx_server_name, fetch(:nginx_server_name, host.to_s)
      set :nginx_server_port, fetch(:nginx_server_port, 80)
    end
  end

  desc 'Setup nginx configuration'
  task :setup do
    on roles :web do
      # sudo_upload! template('nginx_conf.erb'), nginx_sites_available_file
      # sudo :ln, '-fs', nginx_sites_available_file, nginx_sites_enabled_file
      sudo_upload! template('nginx_conf.erb'), centos_nginx_conf_file
    end
  end

  desc 'Setup nginx Diffie-Hellman parameters'
  task :setup_dh_params do
    next unless fetch(:nginx_use_ssl)
    on roles :web do
      next if file_exists?(nginx_dh_params_file) && file_exists?(nginx_dh_params_file)
      sudo :mkdir, '-p', File.dirname(nginx_dh_params_file)
      sudo :openssl, 'dhparam -out', nginx_dh_params_file, '2048'
    end
  end

  task :setup_ssl do
    next unless fetch(:nginx_use_ssl)
    on roles :web do
      next if ENV['force'] != 'true' && file_exists?(nginx_ssl_cert_file) && file_exists?(nginx_ssl_cert_key_file)
      if fetch(:nginx_upload_local_cert)
        sudo_upload! fetch(:nginx_ssl_cert_local_path), nginx_ssl_cert_file
        sudo_upload! fetch(:nginx_ssl_cert_key_local_path), nginx_ssl_cert_key_file
      end
      sudo :chown, 'root:root', nginx_ssl_cert_file
      sudo :chown, 'root:root', nginx_ssl_cert_key_file
    end
  end

  # will generate all commands that nginx supports, for instance:
  # cap ENV nginx:start
  # cap ENV nginx:reload
  # cap ENV nginx:configtest
  %w(start stop reload configtest status force-reload upgrade restart reopen_logs).each do |tsk|
    desc %('#{tsk.capitalize}' nginx command)
    task tsk do
      on roles :web do
        sudo nginx_service_path, tsk
      end
    end
  end

  before :setup, :defaults
  before :setup_dh_params, :defaults
  before :setup_ssl, :defaults

  desc 'service startup on restart'
  task 'service_startup' do
    on roles :web do
      # should be done already:
      sudo 'chkconfig', '--add', nginx_service_name
      sudo 'chkconfig', nginx_service_name, 'on'
    end
  end
  after :setup, :service_startup
end

namespace :deploy do
  after :publishing, 'nginx:reload'
end

desc 'Server setup tasks'
task :setup do
  invoke 'nginx:setup'
  invoke 'nginx:setup_dh_params'
  invoke 'nginx:setup_ssl'
end
