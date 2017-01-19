# Install a hook to run after something changed on a r11k run
#
# @param ensure 'present' or 'absent'. Defaults to 'present'.
# @param hook_source String indicating the source of the hookfile.
# @param hook_content Content of the hook script.
# @param hook_dir String indicating the folder where the hooks are located
#          defaults to `r11k::hooks_dir`
# @param hook_dependencies Array of package names to install as a dependency for this hook.
#   The default ensure parameter is set to whatever the hook as (absent, present) but can
#   be overridden its hash with package specific settings.
# @param config_file String that sets to path of an optional config file you
#          to use for your r11k_hook
# @param config_content Content that gets printed inside the config file.
# @param config_source Source of the config file to provision.
# @param config_umask Override the default umask (0600) for the configuration file.
define r11k::hook (
  Enum['present','absent']       $ensure            = 'present',
  Optional[String]               $hook_content      = undef,
  Optional[String]               $hook_source       = undef,
  Optional[String]               $hook_dir          = undef,
  Optional[Hash[String, Optional[Hash]]] $hook_dependencies = undef,
  Optional[Stdlib::Absolutepath] $config_file       = undef,
  Optional[String]               $config_content    = undef,
  Optional[String]               $config_source     = undef,
  Optional[String]               $config_umask      = '0600',
){

  $real_hooks_dir = $hook_dir ? {
    undef   => $::r11k::default_hooks_dir,
    default => $hook_dir,
  }

  $file_ensure = $ensure ? {
    'absent' => 'absent',
    default  => 'file',
  }
  $package_ensure = $ensure ? {
    'absent' => 'absent',
    default  => 'installed',
  }

  # Validation
  if $ensure == 'present' {
    if $hook_content == undef and $hook_source == undef {
      fail("r11k::hook '${name}': You must provide either the content or the source of the hook")
    }
    if $hook_content != undef and $hook_source != undef {
      fail("r11k::hook '${name}': You must provide either the content or the source of the hook. Not both.")
    }
    if $config_file {
      if $config_content == undef and $config_source == undef {
        fail("r11k::hook '${name}': When using config file, you must provide either the source or the content")
      }
      if $config_content != undef and $config_source != undef {
        fail("r11k::hook '${name}': When using config file, you must provide either the source or the content. Not both")
      }
    }
  }

  file { "${real_hooks_dir}/${name}":
    ensure  => $file_ensure,
    mode    => '0755',
    source  => $hook_source,
    content => $hook_content,
  }

  if $config_file {
    file { $config_file:
      ensure  => $file_ensure,
      mode    => $config_umask,
      content => $config_content,
      source  => $config_source,
      before  => File["${real_hooks_dir}/${name}"],
    }
  }

  if $hook_dependencies {
    $default_params = { 'ensure' => $package_ensure }

    $hook_dependencies.each |String $pname, Optional[Hash] $params| {
      $real_params = merge($default_params, $params)
      package {$pname:
        * => $real_params,
      }
    }
  }
}
