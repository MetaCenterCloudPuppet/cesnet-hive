# == Class: hive
#
# The main configuration class for Apache Hive.
#
class hive (
  $group = undef,
  $hdfs_hostname = undef,
  $metastore_hostname = undef,
  $sentry_hostname = undef,
  $server2_hostname = undef,
  $zookeeper_hostnames = undef,
  $zookeeper_port = undef,
  $realm = '',
  $properties = undef,
  $descriptions = undef,
  $alternatives = '::default',
  $database_setup_enable = true,
  $db = undef,
  $db_host = $hive::params::db_host,
  $db_user = $hive::params::db_user,
  $db_name = $hive::params::db_name,
  $db_password = undef,
  $features = {},
  $confdir = $hive::params::confdir,
  $keytab = '/etc/security/keytab/hive.service.keytab',
  $keytab_source = undef,
  $principal = '::default',
  $schema_dir = undef,
  $schema_file = undef,
) inherits hive::params {
  include ::stdlib

  if $principal == '::default' {
    $_principal = "hive/_HOST@${hive::realm}"
  } else {
    $_principal = $principal
  }

  if $metastore_hostname == $::fqdn {
    case $db {
      'derby',default: {
        $db_properties = {
          'javax.jdo.option.ConnectionURL' => 'jdbc:derby:;databaseName=/var/lib/hive/metastore/metastore_db;create=true',
          'javax.jdo.option.ConnectionDriverName' => 'org.apache.derby.jdbc.EmbeddedDriver',
        }
      }
      'mariadb': {
        $db_properties = {
          'javax.jdo.option.ConnectionURL' => "jdbc:mariadb://${db_host}/${db_name}",
          'javax.jdo.option.ConnectionDriverName' => 'org.mariadb.jdbc.Driver',
          'javax.jdo.option.ConnectionUserName' => $db_user,
          'javax.jdo.option.ConnectionPassword' => $db_password,
          'datanucleus.autoCreateSchema' => false,
          'datanucleus.fixedDatastore' => true,
          'hive.metastore.schema.verification' => true,
        }
      }
      'mysql': {
        $db_properties = {
          'javax.jdo.option.ConnectionURL' => "jdbc:mysql://${db_host}/${db_name}",
          'javax.jdo.option.ConnectionDriverName' => 'com.mysql.jdbc.Driver',
          'javax.jdo.option.ConnectionUserName' => $db_user,
          'javax.jdo.option.ConnectionPassword' => $db_password,
          'datanucleus.autoCreateSchema' => false,
          'datanucleus.fixedDatastore' => true,
          'hive.metastore.schema.verification' => true,
        }
      }
      'postgresql': {
        $db_properties = {
          'javax.jdo.option.ConnectionURL' => "jdbc:postgresql://${db_host}/${db_name}",
          'javax.jdo.option.ConnectionDriverName' => 'org.postgresql.Driver',
          'javax.jdo.option.ConnectionUserName' => $db_user,
          'javax.jdo.option.ConnectionPassword' => $db_password,
          'datanucleus.autoCreateSchema' => false,
          'datanucleus.fixedDatastore' => true,
          'hive.metastore.schema.verification' => true,
        }
      }
      'oracle': {
        $db_properties = {
          'javax.jdo.option.ConnectionURL' => "jdbc:oracle:thin:@//${db_host}/xe",
          'javax.jdo.option.ConnectionDriverName' => 'oracle.jdbc.OracleDriver',
          'javax.jdo.option.ConnectionUserName' => $db_user,
          'javax.jdo.option.ConnectionPassword' => $db_password,
          'datanucleus.autoCreateSchema' => false,
          'datanucleus.fixedDatastore' => true,
          'hive.metastore.schema.verification' => true,
        }
      }
    }
  } else {
    $db_properties = {}
  }

  if $hdfs_hostname {
    $metastore_uri = "hdfs://${hive::hdfs_hostname}"
  } else {
    $metastore_uri = ''
  }
  $dyn_properties = {
    'datanucleus.autoStartMechanism' => 'SchemaTable',
    # recommended value from Cloudera with Impala (default is 600)
    'hive.metastore.client.socket.timeout' => 3600,
    'hive.metastore.warehouse.dir' => "${metastore_uri}/user/hive/warehouse",
  }

  if $hive::metastore_hostname {
    $remote_properties = {
      'hive.metastore.uris' => "thrift://${hive::metastore_hostname}:${hive::port}",
    }
  } else {
    $remote_properties = {}
  }

  if $zookeeper_hostnames {
    $zoo_properties1 = {
      'hive.support.concurrency' => true,
      'hive.zookeeper.quorum' => join($zookeeper_hostnames, ','),
    }
    if $zookeeper_port {
      $zoo_properties2 = {
        'hive.zookeeper.client.port' => $zookeeper_port,
      }
    } else {
      $zoo_properties2 = {}
    }
    $zoo_properties = merge($zoo_properties1, $zoo_properties2)
  } else {
    $zoo_properties = {}
    notice('zookeeper quorum, not specified, recommended for locking')
  }

  if $hive::realm and $hive::realm != '' {
    $sec_common_properties = {
      'hive.metastore.sasl.enabled' => true,
      'hive.metastore.kerberos.keytab.file' => $keytab,
      'hive.metastore.kerberos.principal' => $_principal,
      'hive.security.metastore.authenticator.manager' => 'org.apache.hadoop.hive.ql.security.HadoopDefaultMetastoreAuthenticator',
      'hive.server2.authentication' => 'KERBEROS',
      'hive.server2.authentication.kerberos.principal' => $_principal,
      'hive.server2.authentication.kerberos.keytab' => $keytab,
      'hive.server2.thrift.sasl.qop' => 'auth',
    }
  } else {
    $sec_common_properties = {}
  }
  if $hive::realm and $hive::realm != '' and $hive::sentry_hostname {
    $_group = pick($group, 'hive')
    $_warehouse_mode = '0751'
    $sec_impersonation_properties = {}
    $sec_sentry_properties = {
      'hive.metastore.filter.hook' => 'org.apache.sentry.binding.metastore.SentryMetaStoreFilterHook',
      'hive.metastore.event.listeners' => 'org.apache.sentry.binding.metastore.SentryMetastorePostEventListener',
      'hive.metastore.pre.event.listeners' => 'org.apache.sentry.binding.metastore.MetastoreAuthzBinding',
      'hive.security.authorization.task.factory' => 'org.apache.sentry.binding.hive.SentryHiveAuthorizationTaskFactoryImpl',
      'hive.server2.enable.impersonation' => false,
      'hive.server2.session.hook' => 'org.apache.sentry.binding.hive.HiveAuthzBindingSessionHook',
      'hive.sentry.conf.url' => 'file:///etc/sentry/conf/sentry-site.xml',
    }
  } else {
    $_group = pick($group, 'users')
    $_warehouse_mode = '0755'
    $sec_impersonation_properties = {
      'hive.metastore.pre.event.listeners' => 'org.apache.hadoop.hive.ql.security.authorization.AuthorizationPreEventListener',
      'hive.security.metastore.authorization.manager' => 'org.apache.hadoop.hive.ql.security.authorization.StorageBasedAuthorizationProvider',
      'hive.server2.enable.impersonation' => true,
    }
    $sec_sentry_properties = {}
  }
  $sec_properties = merge($sec_common_properties, $sec_impersonation_properties, $sec_sentry_properties)

  $dyn_descriptions = {
      'javax.jdo.option.ConnectionURL' => 'JDBC connect string for a JDBC metastore',
      'javax.jdo.option.ConnectionDriverName' => 'Driver class name for a JDBC metastore',
      'hive.metastore.event.listeners' => 'turn on metastore-side authorization security (post events)',
      'hive.metastore.pre.event.listeners' => 'turn on metastore-side authorization security',
      'hive.security.metastore.authorization.manager' => 'recommended is the HDFS permissions-based model: StorageBasedAuthorizationProvider',
      'hive.security.metastore.authenticator.manager' => 'just magic from https://cwiki.apache.org/confluence/display/Hive/Storage+Based+Authorization+in+the+Metastore+Server',
      'hive.server2.enable.impersonation' => 'execute queries and access HDFS files as the connected user rather than the super user',
      'hive.server2.thrift.sasl.qop' => 'auth, auth-int, auth-conf (only "auth" is working with Kerberos)',
  }

  $_properties = merge($db_properties, $dyn_properties, $remote_properties, $zoo_properties, $sec_properties, $properties)
  $_descriptions = merge($dyn_descriptions, $descriptions)
}
