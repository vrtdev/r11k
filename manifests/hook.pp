# Install a hook to run after something changed on a r11k run
#
# @param hook_source String indicating the source of the hookfile
# @param hook_folder String indicating the folder where the hooks are located
#          defaults to '/etc/r11k/hooks.d'
# @param hook_dependencies Array of package names to install as a dependency for this hook
# @param config_file String that sets to path of an optional config file you
#          to use for your r11k_hook
# @param config_content String Content that gets printed inside the config file
#
define r11k::hook (
  String $hook_source,
  String $hook_folder = '/etc/r11k/hooks.d',
  Optional[Hash] $hook_dependencies = undef,
  Optional[String] $config_file = undef,
  String $config_content = '',
){

  include ::r11k

  file { "${hook_folder}/${name}":
    ensure => file,
    mode   => '0755',
    source => $hook_source,
  }

  if $config_file {
    file { $config_file:
      ensure  => file,
      content => $config_content,
    }
  }

  if $hook_dependencies {
    create_resources('package', $hook_dependencies)
  }

}
