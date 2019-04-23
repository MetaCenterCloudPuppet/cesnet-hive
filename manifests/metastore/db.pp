# == Class hive::metastore::db
#
# Initialize Hive metastore database.
#
# Requires all install, config, and service classes.
#
class hive::metastore::db {
  include ::stdlib

  $db = $::hive::db ? {
    'derby'         => 'derby',
    /mysql|mariadb/ => 'mysql',
    'postgresql'    => 'postgresql',
    'oracle'        => 'oracle',
    default         => 'derby',
  }

  if $::hive::schema_dir {
    $schema_dir = $::hive::schema_dir
  } else {
    $schema_dir = $::hive::schema_dirs[$db]
  }

  if $::hive::schema_file {
    # schema file specified ==> no facts and no checks
    if $::hive::schema_file =~ /^\// {
      $schema_file = $::hive::schema_file
    } else {
      $schema_file = "${schema_dir}/${::hive::schema_file}"
    }
  } else {
    # schema file not specified ==> autodetect using facts
    if defined('$::hive_schemas') and $::hive_schemas {
      if is_hash($::hive_schemas) {
        $schema_file = $::hive_schemas[$db]
      } else {
        fail('hive_schemas fact not available, set stringify_facts=false in puppet configuration or set hive::schema_file parameter')
      }
    } else {
      notice('hive_schemas fact not available yet, relaunch puppet with Hive installed needed')
      $schema_file = undef
    }
  }

  if $::hive::db and $::hive::database_setup_enable and $schema_file {
    if $db == 'mysql' {
      include ::mysql::server
      include ::mysql::bindings

      #
      # ERROR at line 822: Failed to open file 'hive-txn-schema-0.13.0.mysql.sql', error: 2
      # (resurrection of HIVE-6559, https://issues.apache.org/jira/browse/HIVE-6559)
      #
      # ERROR at line 827: Failed to open file '041-HIVE-16556.mysql.sql', error: 2
      #
      Class['hive::metastore::install']
      ->
      exec{'hive-bug':
        command => "sed -i ${schema_file} -e 's,^SOURCE\\(\\s\\+\\)\\([^/]\\),SOURCE\\1${schema_dir}/\\2,'",
        onlyif  => "grep -q 'SOURCE\\s\\+[^/]' ${schema_file}",
        path    => '/sbin:/usr/sbin:/bin:/usr/bin',
      }
      ->
      mysql::db { 'metastore':
        user     => 'hive',
        password => $hive::db_password,
        grant    => ['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
        sql      => $schema_file,
      }

      Class['hive::metastore::install'] -> Mysql::Db['metastore']
      Mysql::Db['metastore'] -> Class['hive::metastore::service']
      Class['mysql::bindings'] -> Class['hive::metastore::config']
    }

    if ($db == 'postgresql') {
      include postgresql::server
      include postgresql::lib::java

      postgresql::server::db { 'metastore':
        user     => 'hive',
        password => postgresql_password('hive', 'hivepass'),
      }
      ->
      exec { 'metastore-import':
        command => "cat ${schema_file} | psql metastore && touch /var/lib/hive/.puppet-hive-schema-imported",
        path    => '/bin/:/usr/bin',
        user    => 'hive',
        creates => '/var/lib/hive/.puppet-hive-schema-imported',
      }

      include postgresql::lib::java

      Class['hive::metastore::install'] -> Postgresql::Server::Db['metastore']
      Postgresql::Server::Db['metastore'] -> Class['hive::metastore::service']
      Exec['metastore-import'] -> Class['hive::metastore::service']
      Class['postgresql::lib::java'] -> Class['hive::metastore::config']
    }
  }
}
