# Installs the r11k script and creates the default hooks directories.
#
# @param install_location location where to install r11k.
class r11k (
  Optional[Stdlib::Absolutepath] $install_location  = '/usr/local/bin/r11k',
){


  file { $install_location:
    ensure => 'file',
    mode   => '0755',
    source => 'puppet:///modules/r11k/r11k.sh',
  }

  # These are the default directories used in r11k::hook. Make sure they
  # exist to prevent a dependency / recursive directory creation mess
  $default_hooks_dir = '/etc/r11k/hooks.d'

  file {['/etc/r11k','/etc/r11k/hooks.d','/etc/r11k/config']:
    ensure => 'directory',
    mode   => '0755',
  }
}
