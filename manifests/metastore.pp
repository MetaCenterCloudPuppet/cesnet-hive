# == Class hive::metastore
#
# Hive Metastore.
#
class hive::metastore {
  include ::hive::metastore::install
  include ::hive::metastore::config
  include ::hive::metastore::db
  include ::hive::metastore::service

  Class['hive::metastore::install']
  -> Class['hive::metastore::config']
  ~> Class['hive::metastore::service']
  -> Class['hive::metastore']
}
