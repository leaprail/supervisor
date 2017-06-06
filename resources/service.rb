#
# Author:: Noah Kantrowitz <noah@opscode.com>
# Cookbook Name:: supervisor
# Resource:: service
#
# Copyright:: 2011, Opscode, Inc <legal@opscode.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

property :service_name, String, name_property: true
property :command, String
property :process_name, String, default: '%(program_name)s'
property :numprocs, Integer, default: 1
property :numprocs_start, Integer, default: 0
property :priority, Integer, default: 999
property :autostart, [TrueClass, FalseClass], default: true
property :autorestart, [String, Symbol, TrueClass, FalseClass], default: :unexpected
property :startsecs, Integer, default: 1
property :startretries, Integer, default: 3
property :exitcodes, Array, default: [0, 2]
property :stopsignal, [String, Symbol], default: :TERM
property :stopwaitsecs, Integer, default: 10
property :stopasgroup, [NilClass,TrueClass,FalseClass], default: nil
property :killasgroup, [NilClass,TrueClass,FalseClass], default: nil
property :user, [String, NilClass], default: nil
property :redirect_stderr, [TrueClass,FalseClass], default: false
property :stdout_logfile, String, default: 'AUTO'
property :stdout_logfile_maxbytes, String, default: '50MB'
property :stdout_logfile_backups, Integer, default: 10
property :stdout_capture_maxbytes, String, default: '0'
property :stdout_events_enabled, [TrueClass,FalseClass], default: false
property :stderr_logfile, String, default: 'AUTO'
property :stderr_logfile_maxbytes, String, default: '50MB'
property :stderr_logfile_backups, Integer, default: 10
property :stderr_capture_maxbytes, String, default: '0'
property :stderr_events_enabled, [TrueClass, FalseClass], default: false
property :environment, Hash, default: {}
property :directory, [String, NilClass], default: nil
property :umask, [NilClass, String], default: nil
property :serverurl, String, default: 'AUTO'

property :eventlistener, [TrueClass,FalseClass], default: false
property :eventlistener_buffer_size, [NilClass,Integer], default: nil
property :eventlistener_events, [NilClass,Array], default: nil

action :enable do
  converge_by("Enabling #{service_name}") do
    enable_service
  end
end

action :disable do
  if get_current_state(service_name) == 'UNAVAILABLE'
    Chef::Log.info "#{service_name} is already disabled."
  else
    converge_by("Disabling #{service_name}") do
      disable_service
    end
  end
end

action :start do
  case get_current_state(service_name)
  when 'UNAVAILABLE'
    raise "Supervisor service #{service_name} cannot be started because it does not exist"
  when 'RUNNING'
    Chef::Log.debug "#{service_name} is already started."
  when 'STARTING'
    Chef::Log.debug "#{service_name} is already starting."
    wait_til_state("RUNNING")
  else
    converge_by("Starting #{service_name}") do
      if not supervisorctl('start')
        raise "Supervisor service #{service_name} was unable to be started"
      end
    end
  end
end

action :stop do
  case get_current_state(service_name)
  when 'UNAVAILABLE'
    raise "Supervisor service #{service_name} cannot be stopped because it does not exist"
  when 'STOPPED'
    Chef::Log.debug "#{service_name} is already stopped."
  when 'STOPPING'
    Chef::Log.debug "#{service_name} is already stopping."
    wait_til_state("STOPPED")
  else
    converge_by("Stopping #{service_name}") do
      if not supervisorctl('stop')
        raise "Supervisor service #{service_name} was unable to be stopped"
      end
    end
  end
end

action :restart do
  case get_current_state(service_name)
  when 'UNAVAILABLE'
    raise "Supervisor service #{service_name} cannot be restarted because it does not exist"
  else
    converge_by("Restarting #{service_name}") do
      if not supervisorctl('restart')
        raise "Supervisor service #{service_name} was unable to be started"
      end
    end
  end
end

action_class.class_eval do
  def enable_service
    e = execute "supervisorctl update" do
      action :nothing
      user "root"
    end

    t = template "#{node['supervisor']['dir']}/#{new_resource.service_name}.conf" do
      source "program.conf.erb"
      cookbook "supervisor"
      owner "root"
      group "root"
      mode "644"
      variables({
        :service_name => service_name,
        :process_name => process_name,
        :command  => command,
        :numprocs => numprocs,
        :numprocs_start => numprocs_start,
        :priority => priority,
        :autostart => autostart,
        :autorestart => autorestart,
        :startsecs => startsecs,
        :startretries => startretries,
        :exitcodes => exitcodes,
        :stopsignal => stopsignal,
        :stopwaitsecs => stopwaitsecs,
        :stopasgroup => stopasgroup,
        :killasgroup => killasgroup,
        :user => user,
        :redirect_stderr => redirect_stderr,
        :stdout_logfile => stdout_logfile,
        :stdout_logfile_maxbytes => stdout_logfile_maxbytes,
        :stdout_logfile_backups => stdout_logfile_backups,
        :stdout_capture_maxbytes => stdout_capture_maxbytes,
        :stdout_events_enabled => stdout_events_enabled,
        :stderr_logfile => stderr_logfile,
        :stderr_logfile_maxbytes => stderr_logfile_maxbytes,
        :stderr_logfile_backups => stderr_logfile_backups,
        :stderr_capture_maxbytes => stderr_capture_maxbytes,
        :stderr_events_enabled => stderr_events_enabled,
        :environment => environment,
        :directory => directory,
        :umask => umask,
        :serverurl => serverurl,
        :eventlistener => eventlistener,
        :eventlistener_events => eventlistener_events,
        :eventlistener_buffer_size => eventlistener_buffer_size
      })
      notifies :run, "execute[supervisorctl update]", :immediately
    end

    t.run_action(:create)
    if t.updated?
      e.run_action(:run)
    end
  end

  def disable_service
    execute "supervisorctl update" do
      action :nothing
      user "root"
    end

    file "#{node['supervisor']['dir']}/#{new_resource.service_name}.conf" do
      action :delete
      notifies :run, "execute[supervisorctl update]", :immediately
    end
  end

  def supervisorctl(action)
    cmd = "supervisorctl #{action} #{cmd_line_args} | grep -v ERROR"
    result = Mixlib::ShellOut.new(cmd).run_command
    # Since we append grep to the command
    # The command will have an exit code of 1 upon failure
    # So 0 here means it was successful
    result.exitstatus == 0
  end

  def cmd_line_args
    name = new_resource.service_name
    if new_resource.process_name != '%(program_name)s'
      name += ':*'
    end
    name
  end

  def get_current_state(service_name)
    result = Mixlib::ShellOut.new("supervisorctl status").run_command
    match = result.stdout.match("(^#{service_name}(\\:\\S+)?\\s*)([A-Z]+)(.+)")
    if match.nil?
      "UNAVAILABLE"
    else
      match[3]
    end
  end

  def wait_til_state(state,max_tries=20)
    service = new_resource.service_name

    max_tries.times do
      return if get_current_state(service) == state

      Chef::Log.debug("Waiting for service #{service} to be in state #{state}")
      sleep 1
    end

    raise "service #{service} not in state #{state} after #{max_tries} tries"
  end

end
