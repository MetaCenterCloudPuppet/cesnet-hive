# == Class hive::server2::service
#
class hive::server2::service {
  service { $hive::daemons['server']:
    ensure    => 'running',
    enable    => true,
    subscribe => [File["${hive::confdir}/hive-site.xml"]],
  }

  # launch metastore first if collocated with server2
  # (dependency is not strictly required though, server2 can wait for
  # metastore, but let's not throw exceptions to logs)
  if $hive::metastore_hostname == $::fqdn {
    include ::hive::metastore::service
    Class['hive::metastore::service'] -> Class['hive::server2::service']
  }
}
