# == Class hive::frontend
#
# Hive client.
#
class hive::frontend {
  include ::hive::frontend::install
  include ::hive::frontend::config

  Class['hive::frontend::install']
  -> Class['hive::frontend::config']
  -> Class['hive::frontend']
}
