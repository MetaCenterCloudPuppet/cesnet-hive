# == Class hive::server2
#
# Hive server2.
#
class hive::server2 {
  include ::hive::server2::install
  include ::hive::server2::config
  include ::hive::server2::service

  Class['hive::server2::install']
  -> Class['hive::server2::config']
  ~> Class['hive::server2::service']
  -> Class['hive::server2']
}
