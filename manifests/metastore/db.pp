# == Class hive::metastore::db
#
# Initialize Hive metastore database.
#
# Requires included all install, config, and service classes, but the dependencies themselves are inside.
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
      mysql::db { $::hive::db_name:
        user     => $::hive::db_user,
        password => $::hive::db_password,
        grant    => ['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
        sql      => $schema_file,
      }

      Class['hive::metastore::install'] -> Mysql::Db[$::hive::db_name]
      Mysql::Db[$::hive::db_name] -> Class['hive::metastore::service']
      Class['mysql::bindings'] -> Class['hive::metastore::config']
    }

    if ($db == 'postgresql') {
      postgresql::server::db { $::hive::db_name:
        user     => $::hive::db_user,
        password => postgresql_password($::hive::db_user, $::hive::db_password),
      }
      ->
      exec { 'metastore-import':
        command => "cat ${schema_file} | psql metastore && touch /var/lib/hive/.puppet-hive-schema-imported",
        path    => '/bin/:/usr/bin',
        user    => 'hive',
        creates => '/var/lib/hive/.puppet-hive-schema-imported',
      }

      include postgresql::lib::java

      Class['hive::metastore::install'] -> Postgresql::Server::Db[$::hive::db_name]
      Postgresql::Server::Db[$::hive::db_name] -> Class['hive::metastore::service']
      Exec['metastore-import'] -> Class['hive::metastore::service']
      Class['postgresql::lib::java'] -> Class['hive::metastore::config']
    }
  }
}
