# == Class hive::common::daemon
#
# Common settings for Hive daemons.
#
class hive::common::daemon {
  include ::hive::user

  if $hive::realm and $hive::realm != '' {
    file { $::hive::keytab:
      owner => 'hive',
      group => 'hive',
      mode  => '0400',
      alias => 'hive.service.keytab',
    }
  }

  if $hive::features['manager'] {
    file { '/usr/local/sbin/hivemanager':
      owner   => 'root',
      group   => 'root',
      mode    => '0755',
      alias   => 'hivemanager',
      content => template('hive/hivemanager.erb'),
    }
  }

  Class['hive::user'] -> Class['hive::common::daemon']
}
