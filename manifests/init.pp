# Installs the r11k script and creates the default hooks directories.
#
# @param install_location location where to install r11k.
# @param crons  Hash with r11k:cron definitions to create.
# @param hooks Hash with r11k::hook definitions to create.
# @param purge_hooks Should we purge unmanaged files from the default hook directories.
class r11k (
  Optional[Stdlib::Absolutepath] $install_location  = '/usr/local/bin/r11k',
  Hash $crons = {},
  Hash $hooks = {},
  Boolean $purge_hooks = false,
){

  file { $install_location:
    ensure => 'file',
    mode   => '0755',
    source => 'puppet:///modules/r11k/r11k.sh',
  }

  # These are the default directories used in r11k::hook. Make sure they
  # exist to prevent a dependency / recursive directory creation mess
  $default_hooks_dir = '/etc/r11k/hooks.d'
  $default_env_hooks_dir = '/etc/r11k/env.hooks.d'

  file {'/etc/r11k':
    ensure => 'directory',
    mode   => '0755',
  }
  file {'/etc/r11k/config':
    ensure => 'directory',
    mode   => '0750',
  }

  file {[$default_hooks_dir, $default_env_hooks_dir]:
    ensure  => 'directory',
    mode    => '0755',
    purge   => $purge_hooks,
    recurse => $purge_hooks,
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
