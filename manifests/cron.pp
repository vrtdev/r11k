# Manage a cronjob to run r11k
#
# @param git_base_repo local checkkout/mirror or remote of the git repository to deploy to environments.
# @param ensure Value can be either 'present' or 'absent'. Defaults to 'present'.
# @param basedir puppet environments folder location. Defaults to 'this' puppet-server's setting.
# @param cachedir Custom cache dir to use. Defaults to no setting and uses whatever default the script has.
# @param hooksdir Custom hooks dir to use. Defaults to `r11k::default_hooks_dir`.
# @param job A hash with cron settings passed through to the cronjob.
# @param includes Array (or single String) with regex filters with branches to convert to environments.
define r11k::cron (
  String                          $git_base_repo,
  Enum['present','absent']        $ensure           = 'present',
  Stdlib::Absolutepath            $basedir          = $::settings::environmentpath,
  Optional[Stdlib::Absolutepath]  $cachedir         = undef,
  Optional[Stdlib::Absolutepath]  $hooksdir         = undef,
  Hash[String,Any]                $job              = { 'minute' => '*/4', },
  Optional[Variant[String, Array[String]]] $includes = undef,
) {

  $r11k_location = $::r11k::install_location
  $cmd_basedir = ['--basedir', $basedir, '--no-wait']

  $cmd_cachedir = $cachedir ? {
    undef   => [],
    default => ['--cachedir', $cachedir],
  }

  $cmd_hooksdir  = $hooksdir ? {
    undef   => ['--hooksdir', $::r11k::default_hooks_dir],
    default => ['--hooksdir', $hooksdir ],
  }

  case $includes {
    undef: { $cmd_includes = [] }
    String: { $cmd_includes = ['--include', $includes] }
    default: {
      if empty ($includes) {
        $cmd_includes = []
      }
      else {
        $cmd_includes = ['--include', join($includes,':')]
      }
    }
  }

  $command_array = flatten([
    $r11k_location,
    $cmd_basedir,
    $cmd_cachedir,
    $cmd_hooksdir,
    $cmd_includes,
    $git_base_repo,
  ])

  cron {"r11k::cron: ${name}":
    ensure  => $ensure,
    command => shell_join($command_array),
    require => File[$r11k_location],
    *       => $job,
  }
}
