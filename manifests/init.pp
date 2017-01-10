# Installs the r11k script and creates the default hooks directories.
#
# @param install_location location where to install r11k.
# @param default_hooks_dir default hooks directory to use for custom hooks. NOT used in cronjobs.
class r11k (
  Optional[Stdlib::Absolutepath] $install_location  = '/usr/local/bin/r11k',
  Optional[Stdlib::Absolutepath] $default_hooks_dir = '/etc/r11k/hooks.d',
){

  file { $install_location:
    ensure => 'file',
    mode   => '0755',
    source => 'puppet:///modules/r11k/r11k.sh',
  }

  file {['/etc/r11k','/etc/r11k/hooks.d','/etc/r11k/config']:
    ensure => 'directory',
    mode   => '0755',
  }
}
