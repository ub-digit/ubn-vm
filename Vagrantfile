# -*- mode: ruby -*-
# vi: set ft=ruby :
VAGRANTFILE_API_VERSION = "2"
Vagrant.require_version '>= 1.8.1'

# Absolute paths on the host machine.
host_config_dir = File.dirname(File.expand_path(__FILE__))

# Cross-platform way of finding an executable in the $PATH.
def which(cmd)
  exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
  ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
    exts.each do |ext|
      exe = File.join(path, "#{cmd}#{ext}")
      return exe if File.executable?(exe) && !File.directory?(exe)
    end
  end
  nil
end

def walk(obj, &fn)
  if obj.is_a?(Array)
    obj.map { |value| walk(value, &fn) }
  elsif obj.is_a?(Hash)
    obj.each_pair { |key, value| obj[key] = walk(value, &fn) }
  else
    obj = yield(obj)
  end
end

require 'yaml'
# Load default VM configurations.
vconfig = YAML.load_file("#{host_config_dir}/default.config.yml")

# Load stages configs
Dir.glob("#{host_config_dir}/stages_config/*.yml") do |stages_config_file_path|
    vconfig.merge!(YAML.load_file(stages_config_file_path))
end

# Use optional config.yml and local.config.yml for configuration overrides.
['config.yml', 'local.config.yml'].each do |config_file|
  if File.exist?("#{host_config_dir}/#{config_file}")
    vconfig.merge!(YAML.load_file("#{host_config_dir}/#{config_file}"))
  end
end

# Replace jinja variables in config.
vconfig = walk(vconfig) do |value|
  while value.is_a?(String) && value.match(/{{ .* }}/)
    value = value.gsub(/{{ (.*?) }}/) { vconfig[Regexp.last_match(1)] }
  end
  value
end

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.hostname = vconfig['vagrant_hostname']
  if vconfig['vagrant_ip'] == "0.0.0.0" && Vagrant.has_plugin?("vagrant-auto_network")
    config.vm.network :private_network, :ip => vconfig['vagrant_ip'], :auto_network => true
  else
    config.vm.network :private_network, ip: vconfig['vagrant_ip']
  end
  # TODO: Replace with secure key! (Needed for drush aliases)
  config.ssh.insert_key = false
  config.ssh.forward_agent = true

  config.vm.box = vconfig['vagrant_box']

  # If hostsupdater plugin is installed, add all servernames as aliases.
  if Vagrant.has_plugin?('vagrant-hostmanager')
    config.hostmanager.enabled = true
    config.hostmanager.manage_host = true
    config.hostmanager.manage_guest = false
    config.hostmanager.aliases = []
    vconfig['apache_vhosts'].each do |host|
      config.hostmanager.aliases.push(host['servername'])
      config.hostmanager.aliases.concat(host['serveralias'].split) if host['serveralias']
    end
  end

  vconfig['vagrant_synced_folders'].each do |synced_folder|
    options = {
      type: synced_folder['type'],
      rsync__auto: 'true',
      rsync__exclude: synced_folder['excluded_paths'],
      rsync__args: ['--verbose', '--archive', '--delete', '-z', '--chmod=ugo=rwX'],
      id: synced_folder['id'],
      create: synced_folder.include?('create') ? synced_folder['create'] : false,
      mount_options: synced_folder.include?('mount_options') ? synced_folder['mount_options'] : nil
    }
    if synced_folder.include?('options_override')
      options = options.merge(synced_folder['options_override'])
    end
    config.vm.synced_folder synced_folder['local_path'], synced_folder['destination'], options
  end

  # Provision using Ansible provisioner if Ansible is installed on host.
  if which('ansible-playbook')
    config.vm.provision "ansible" do |ansible|
      ansible.playbook = "#{host_config_dir}/provisioning/playbook.yml"
      ansible.sudo = true #???
      ansible.raw_ssh_args = ['-o ForwardAgent=yes'] #VS config.ssh.forward_agent?
      # ansible.verbose = "vvv"
    end
  # Provision using shell provisioner and JJG-Ansible-Windows otherwise.
  else
    raise 'Ansible not found!'
  end

  # VirtualBox.
  config.vm.provider :virtualbox do |v|
    v.name = vconfig['vagrant_hostname']
    v.memory = vconfig['vagrant_memory']
    v.cpus = vconfig['vagrant_cpus']
    v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    v.customize ["modifyvm", :id, "--ioapic", "on"]
  end

  # Set the name of the VM. See: http://stackoverflow.com/a/17864388/100134
  config.vm.define vconfig['vagrant_machine_name'] do |d|
  end
end
