# == Class: r11k::install
#
class r11k::install {
  # resources
  file { '/usr/local/bin/r11k':
    ensure => file,
    mode   => '0755',
    source => 'puppet:///modules/r11k/r11k.sh',
  }
}
