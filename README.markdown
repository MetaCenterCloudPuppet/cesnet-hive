## Apache Hive Puppet Module

[![Build Status](https://travis-ci.org/MetaCenterCloudPuppet/cesnet-hive.svg?branch=master)](https://travis-ci.org/MetaCenterCloudPuppet/cesnet-hive)

####Table of Contents

1. [Module Description - What the module does and why it is useful](#module-description)
2. [Setup - The basics of getting started with Hive](#setup)
    * [What cesnet-hive module affects](#what-hive-affects)
    * [Setup requirements](#setup-requirements)
    * [Beginning with hive](#beginning-with-hive)
3. [Usage - Configuration options and additional functionality](#usage)
    * [Enable Security](#security)
    * [Multihome Support](#multihome)
    * [Cluster with more HDFS Name nodes](#multinn)
    * [Upgrade](#upgrade)
4. [Reference - An under-the-hood peek at what the module is doing and how](#reference)
    * [Classes](#classes)
    * [Module Parameters (hive class)](#class-hive)
5. [Limitations - OS compatibility, etc.](#limitations)
6. [Development - Guide for contributing to the module](#development)

<a name="module-description"></a>
##Module Description

This module installs and setups Apache Hive data warehouse software running on the top of Hadoop cluster. Hive services can be collocated or separated in the cluster. Optionally security based on Kerberos can be enabled. Security should be enabled if Hadoop cluster security is enabled.

Supported are:

* **Fedora 21**: only hive and hcatalog clients, native packages (tested on Hive 0.12.0)
* **Debian 7/wheezy**: Cloudera distribution (tested on Hive 0.13.1)
* **RHEL 6 and clones**: Cloudera distribution (tested with Hadoop 2.6.0)

Puppet 3.x is required.

<a name="setup"></a>
##Setup

<a name="what-hive-affects"></a>
###What cesnet-hive module affects

* Packages: installs Hive packages (common packages, subsets for requested services, hcatalog, and/or hive client)
* Files modified:
 * */etc/hive/\** (or */etc/hive/conf/\**)
 * */usr/local/sbin/hivemanager* (not needed, only when administrator manager script is requested by *features*)
* Alternatives:
 * alternatives are used for */etc/hive/conf* in Cloudera
 * this module switches to the new alternative by default, so the Cloudera original configuration can be kept intact
* Services: only requested Hive services are setup and started
 * metastore
 * server2
* Helper Files:
 * */var/lib/hadoop-hdfs/.puppet-hive-dir-created* (created by cesnet-hadoop module)
* Secret Files (keytabs): permissions are modified for hive service keytab (*/etc/security/keytab/hive.service.keytab*)

<a name="setup-requirements"></a>
###Setup Requirements

There are several known or intended limitations in this module.

Be aware of:

* **Repositories** - see *cesnet-hadoop* module Setup Requirements for details

* **No inter-node dependencies**: running HDFS namenode is required for Hive metastore server startup

* **Secure mode**: keytabs must be prepared in /etc/security/keytabs/ (see *realm* parameter)

* **Database setup not handled here**: basic database setup and database creation needs to be handled externally; tested are puppetlabs-mysql and puppetlabs-postgresql modules (see examples), but it is not limited to these modules

* **Hadoop**: it should be configured locally or you should use *hdfs\_hostname* parameter (see [Module Parameters](#class-hive))

<a name="beginning-with-hive"></a>
###Beginning with Hive

Let's start with basic examples.

**Example**: The simplest setup without security nor zookeeper, with everything on single machine:

    class{"hive":
      hdfs_hostname => $::fqdn,
      metastore_hostname => $::fqdn,
      server2_hostname => $::fqdn,
      # security needs to be disabled explicitly by using empty string
      realm => '',
    }

    node <HDFS_NAMENODE> {
      # HDFS initialization must be done on the namenode
      # (or /user/hive on HDFS must be created)
      include hive::hdfs
    }

    node default {
      # server
      include hive::metastore
      include hive::server2
      # client
      include hive::frontend
      include hive::hcatalog
    }

Modify *$::fqdn* and node(s) section as needed.

We recommend:

* using zookeeper and set hive parameter *zookeeper\_hostnames* (cesnet-zookeeper module can be used for installation of zookeeper)
* if collocated with HDFS namenode, add dependency *Class['hadoop::namenode::service'] -> Class['hive::metastore::service']*
* if not collocated, it is needed to have HDFS namenode running first, or restart Hive metastore later

<a name="usage"></a>
##Usage

It is highly recommended to use real database backends instead of Derby. Also security can be enabled.

See the examples:


**Example 1**: Setup with security:

Additional permissions in Hadoop cluster are needed: add hive proxy user.

    class{"hadoop":
    ...
      properties => {
        'hadoop.proxyuser.hive.groups' => 'hive,users',
        'hadoop.proxyuser.hive.hosts' => '*',
      },
    ...
    }

    class{"hive":
      group => 'users',
      metastore_hostname => $::fqdn,
      realm => 'MY.REALM',
    }

Use nodes sections from the initial **Example**, modify *$::fqdn* and nodes sections as needed.


**Example 2**: MySQL database, puppetlabs-mysql puppet module is used here.

Add this to the initial example:

    class{"hive":
      ...
      db => 'mysql',
      db_password => 'hivepassword',
    }

    node default {
      ...

      class { 'mysql::server':
        root_password  => 'strongpassword',
      }
    
      mysql::db { 'metastore':
        user     => 'hive',
        password => 'hivepassword',
        host     => 'localhost',
        grant    => ['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
        sql      => '/usr/lib/hive/scripts/metastore/upgrade/mysql/hive-schema-0.13.0.mysql.sql',
      }
    
      class { 'mysql::bindings':
        java_enable => true,
      }
    
      Class['hive::metastore::install'] -> Mysql::Db['metastore']
      Mysql::Db['metastore'] -> Class['hive::metastore::service']
      Class['mysql::bindings'] -> Class['hive::metastore::config']
    }

As you can see, between *hive::metastore::install* and *hive::metastore::service* is included creation of the metastore MySQL database. The reason is the required schema SQL file goes from Hive packages, and the database is then needed for running Hive metastore.

The JDBC jar-file is also needed for metastore.


**Example 3**: PostgreSQL database, puppetlabs-postgresql puppet module is used here.

Add this to the initial example:

    class{"hive":
      ...
      db => 'postgresql',
      db_password => 'hivepassword',
    }

    node default {
      ...

      class { 'postgresql::server':
        postgres_password => 'strongpassword',
      }

      postgresql::server::db { 'metastore':
        user     => 'hive',
        password => postgresql_password('hive', 'hivepass'),
      }
      ->
      exec { 'metastore-import':
        command => 'cat /usr/lib/hive/scripts/metastore/upgrade/postgres/hive-schema-0.13.0.postgres.sql | psql metastore && touch /var/lib/hive/.puppet-hive-schema-imported',
        path    => '/bin/:/usr/bin',
        user    => 'hive',
        creates => '/var/lib/hive/.puppet-hive-schema-imported',
      }

      include postgresql::lib::java

      Class['postgresql::lib::java'] -> Class['hive::metastore::config']
      Class['hive::metastore::install'] -> Postgresql::Server::Db['metastore']
      Postgresql::Server::Db['metastore'] -> Class['hive::metastore::service']
      Exec['metastore-import'] -> Class['hive::metastore::service']
    }

Like with MySQL, between *hive::metastore::install* and *hive::metastore::service* is included creation of the metastore database, now PostgreSQL. The reason is the required schema SQL file goes from Hive packages, and the database is then needed for running Hive metastore.

The JDBC jar-file is also needed for metastore.


<a name="security"></a>
###Enable Security

Security in Hadoop (and Hive) is based on Kerberos. Keytab files needs to be prepared on the proper places before enabling the security.

Following parameters are used for security (see also hive class):

* *realm* (required parameter, empty string disables the security)<br />
  Enable security and Kerberos realm to use. Empty string disables the security.
  To enable security, there are required:
  * installed Kerberos client (Debian: krb5-user/heimdal-clients; RedHat: krb5-workstation)
  * configured Kerberos client (*/etc/krb5.conf*, */etc/krb5.keytab*)
  * */etc/security/keytab/hive.service.keytab* (on all server nodes)

<a name="multihome"></a>
###Multihome Support

Multihome is supported by Hive out-of-the-box.

<a name="multinn"></a>
###Cluster with more HDFS Name nodes

If there are used more HDFS namenodes in the Hadoop cluster (high availability, namespaces, ...), it is needed to have 'hive' system user on all of them to autorization work properly. You could install full Hive client (using *hive::frontend::install*), but just creating the user is enough (using *hive::user*).

Note, the *hive::hdfs* class must be used too, but only on one of the HDFS namenodes. It includes the *hive::user*.

**Example**:

    node <HDFS_NAMENODE> {
      include hive::hdfs
    }

    node <HDFS_OTHER_NAMENODE> {
      include hive::user
    }


<a name="upgrade"></a>
###Upgrade

The best way is to refresh configrations from the new original (=remove the old) and relaunch puppet on top of it. There is also needed to update schema using *schematool* or upgrade scripts in */usr/lib/hive/scripts/metastore/upgrade/DATABASE/*.

For example (using mysql, from Hive 0.13.0):

    alternative='cluster'
    d='hive'
    mv /etc/{d}$/conf.${alternative} /etc/${d}/conf.cdhXXX
    update-alternatives --auto ${d}-conf

    # upgrade
    ...

    # metadata schema upgrade
    mysqldump --opt metastore > metastore-backup.sql
    mysqldump --skip-add-drop-table --no-data metastore > my-schema-backup.mysql.sql
    /usr/lib/hive/bin/schematool -dbType mysql -upgradeSchemaFrom 0.13.0 -userName root -passWord MYSQL_ROOT_PASSWORD

    puppet agent --test
    #or: puppet apply ...


<a name="reference"></a>
##Reference

<a name="classes"></a>
###Classes

* [**`hive`**](#class-hive): The main configuration class for Apache Hive
* **`hive::hbase`**: Client Support for HBase
* **`hive::hdfs`**: HDFS initialiations
* `hive::params`
* `hive::service`
* common:
 * `hive::common::config`
 * `hive::common::daemon`
 * `hive::common::postinstall`
* **`hive::frontend`**: Hive Client
 * `hive::frontend::config`
 * `hive::frontend::install`
* **`hive::hcatalog`**: Hive HCatalog Client
 * `hive::hcatalog::config`
 * `hive::hcatalog::install`
* **`hive::metastore`**: Hive Metastore
 * `hive::metastore::config`
 * `hive::metastore::install`
 * `hive::metastore::service`
* **`hive::server2`**: Hive Server
 * `hive::server2::config`
 * `hive::server2::install`
 * `hive::server2::service`
* **`hive::user`**: Create hive system user, if needed

<a name="class-hive"></a>
###`hive` class

####`group`

Group where all users belong. Default: 'users'.

It is not updated when changed, you should remove the /var/lib/hadoop-hdfs/.puppet-hive-dir-created file when changing or update group of /user/hive on HDFS.

####`hdfs_hostname`

HDFS hostname (or defaultFS value), if different from core-site.xml Hadoop file. Default: undef.

It is recommended to have the *core-site.xml* file instead. *core-site.xml* will be created when installing any Hadoop component or if you include *hadoop::common::config* class.

####`metastore_hostname`

Hostname of the metastore server. Default: undef.

When specified, remote mode is activated (recommended).

####`server2_hostname`

Hostname of the Hive server. Default: undef.

Used only for hivemanager script.

####`zookeeper_hostnames`

Array of zookeeper hostnames quorum. Default: undef.

Used for lock management (recommended).

####`zookeeper_port`

Zookeeper port, if different from the default (2181). Default: undef.

####`realm`

Kerberos realm. Defaukt: undef.

Use empty string if Kerberos is not used.

When security is enabled, you also need to add these properties to Hadoop cluster:

* hadoop.proxyuser.hive.groups => 'hadoop,users' (where 'users' is the group in *group* parameter)
* hadoop.proxyuser.hive.hosts => '\*'

####`properties`

Additional properties. Default: undef.

####`descriptions`

Descriptions for the additional properties. Default: undef.

####`alternatives`

Use alternatives to switch configuration. Default: 'cluster' or undef.

Use it only when supported (like with Cloudera for example).

####`db`

Database behind the metastore. Default: undef.

The default is embeded database (*derby*), but it is recommended to use proper database.

Values:

* *derby* (default): embeded database
* *mysql*: MySQL/MariaDB,
* *postgresql*: PostgreSQL

####`db_host`

Database hostname for *mysql*, *postgresql*, and *oracle*'. Default: 'localhost'.

It can be overriden by *javax.jdo.option.ConnectionURL* property.

####`db_name`

Database name for *mysql* and *postgresql*. Default: 'metastore'.

For *oracle* 'xe' schema is used. Can be overriden by *javax.jdo.option.ConnectionURL* property.

####`db_user`

Database user for *mysql*, *postgresql*, and *oracle*. Default: 'hive'.

####`db_password`

Database password for *mysql*, *postgresql*, and *oracle*. Default: undef.

####`features`

Enable additional features. Default: {}.

Values:

* **manager** - script in /usr/local to start/stop Hive daemons relevant for given node


<a name="limitations"></a>
##Limitations

Idea in this module is to do only one thing - setup Hive SW - and not limit generic usage of this module by doing other stuff. You can have your own repository with Hadoop SW, you can select which Kerberos implementation, Java version, or database puppet module to use.

On other hand this leads to some limitations as mentioned in [Setup Requirements](#setup-requirements) section and usage is more complicated - you may need site-specific puppet module together with this one.

<a name="development"></a>
##Development

* Repository: [https://github.com/MetaCenterCloudPuppet/cesnet-hive](https://github.com/MetaCenterCloudPuppet/cesnet-hive)
* Tests:
 * basic: see *.travis.yml*
 * vagrant: [https://github.com/MetaCenterCloudPuppet/hadoop-tests](https://github.com/MetaCenterCloudPuppet/hadoop-tests)
* Email: František Dvořák &lt;valtri@civ.zcu.cz&gt;
