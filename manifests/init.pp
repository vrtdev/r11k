# Installs the r11k script and creates the default hooks directories.
#
# @param install_location location where to install r11k.
# @param crons  Hash with r11k:cron definitions to create.
# @param hooks Hash with r11k::hook definitions to create.
class r11k (
  Optional[Stdlib::Absolutepath] $install_location  = '/usr/local/bin/r11k',
  Hash $crons = {},
  Hash $hooks = {},
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

  $crons.each |$name, $params| {
    ::r11k::cron {$name:
      * => $params,
    }
  }

  $hooks.each |$name, $params| {
    ::r11k::hook {$name:
      * => $params,
    }
  }
}
