/*

== Definition: varnish::instance

Creates a running varnishd instance and configures it's different startup
parameters. Optionnally a VCL configuration file can be provided. Have a look
at http://varnish.projects.linpro.no/wiki/Introduction for more details.


Parameters:
- *listen_address*: address of varnish's http service, defaults to all interfaces.
- *listen_port*: port varnish's http service must listen to, defaults to 6081.
- *admin_address*: address of varnish's admin console, defaults to localhost.
- *admin_port*: port of varnish's admin console, defaults to 6082.
- *backend*: location of the backend, in the "address:port" format. This is
  passed to "varnishd -b". Defaults to none.
- *vcl_file*: location of the instance's VCL file, located on puppet's
  fileserver (puppet://host/module/path.vcl). This is passed to "varnishd -f".
  Defaults to none.
- *vcl_content*: content of the instance's VCL file. Defaults to none.
- *storage_size*: size of varnish's cache, either in bytes (with a K/M/G/T suffix)
  or in percentage of the space left on the device. Defaults to 50%.
- *storage*: complete storage string, usually something like
  "file,/var/lib/varnish/varnish_storage.bin,1G".
- *params*: array of "key=value" strings to be passed to "varnishd -p"
  (run-time parameters). Defaults to none.
- *nfiles*: max number of open files (ulimit -n) allocated to varnishd,
  defaults to 131072.
- *memlock*: max memory lock size (ulimit -l) allocated to varnishd, defaults
  to 82000.
- *corelimit*: size of coredumps (ulimit -c). Usually "unlimited" or 0,
  defaults to 0.
- *varnishlog*: whether a varnishlog instance must be run together with
  varnishd. defaults to true.

See varnishd(1) and /etc/{default,sysconfig}/varnish for more details.

Notes:
- varnish's configuration will be reloaded when it changes, using
  /usr/local/sbin/vcl-reload.sh

Requires:
- Class["varnish"]
- gcc if a VCL configuration file is used.


Example usage:

  include varnish

  varnish::instance { "foo":
    backend        => "10.0.0.2:8080",
    listen_address => "192.168.1.10",
    listen_port    => "80",
    admin_port     => "6082",
    storage_size   => "5G",
    params         => ["thread_pool_min=1",
                       "thread_pool_max=1000",
                       "thread_pool_timeout=120"],
  }

  varnish::instance { "bar":
    listen_address => "192.168.1.11",
    listen_port    => "80",
    admin_port     => "6083",
    vcl_file       => "puppet:///barproject/varnish.vcl",
    corelimit      => "unlimited",
  }

*/
define varnish::instance($listen_address="",
                         $listen_port="6081",
                         $admin_address="localhost",
                         $admin_port="6082",
                         $backend=false,
                         $vcl_file=false,
                         $vcl_content=false,
                         $storage_size="50%",
                         $storage=false,
                         $params=[],
                         $nfiles="131072",
                         $memlock="82000",
                         $corelimit="0",
                         $varnishlog=true) {

  # use a more comprehensive attribute name for ERB templates.
  $instance = $name

  # All the startup options are defined in /etc/{default,sysconfig}/varnish-nnn
  file { "varnish-${instance} startup config":
    ensure  => present,
    content => template("varnish/varnish.erb"),
    name    => $operatingsystem ? {
      Debian => "/etc/default/varnish-${instance}",
      Ubuntu => "/etc/default/varnish-${instance}",
      RedHat => "/etc/sysconfig/varnish-${instance}",
      Fedora => "/etc/sysconfig/varnish-${instance}",
    },
  }

  if ($vcl_file != false) {
    file { "/etc/varnish/${instance}.vcl":
      ensure  => present,
      source  => $vcl_file,
      notify  => Service["varnish-${instance}"],
      require => Package["varnish"],
    }
  }

  if ($vcl_content != false) {
    file { "/etc/varnish/${instance}.vcl":
      ensure  => present,
      content => $vcl_content,
      notify  => Service["varnish-${instance}"],
      require => Package["varnish"],
    }
  }

  file { "/var/lib/varnish/${instance}":
    ensure => directory,
    owner  => "root",
  }

  file { "/etc/init.d/varnish-${instance}":
    ensure  => present,
    mode    => 0755,
    owner   => "root",
    group   => "root",
    content => $operatingsystem ? {
      Debian => template("varnish/varnish.debian.erb"),
      Ubuntu => template("varnish/varnish.debian.erb"),
      RedHat => template("varnish/varnish.redhat.erb"),
      CentOS => template("varnish/varnish.redhat.erb"),
      Fedora => template("varnish/varnish.redhat.erb"),
    },
  }

  file { "/etc/init.d/varnishlog-${instance}":
    ensure  => present,
    mode    => 0755,
    owner   => "root",
    group   => "root",
    content => $operatingsystem ? {
      Debian => template("varnish/varnishlog.debian.erb"),
      Ubuntu => template("varnish/varnishlog.debian.erb"),
      RedHat => template("varnish/varnishlog.redhat.erb"),
      CentOS => template("varnish/varnishlog.redhat.erb"),
      Fedora => template("varnish/varnishlog.redhat.erb"),
    },
  }

  service { "varnish-${instance}":
    enable  => true,
    ensure  => running,
    pattern => "/var/run/varnishd-${instance}.pid",
    # reload VCL file when changed, without restarting the varnish service.
    restart => "/usr/local/sbin/vcl-reload.sh /etc/varnish/${instance}.vcl",
    require => [
      File["/etc/init.d/varnish-${instance}"],
      File["/usr/local/sbin/vcl-reload.sh"],
      File["varnish-${instance} startup config"],
      File["/var/lib/varnish/${instance}"],
      Service["varnish"],
      Service["varnishlog"]
    ],
  }

  if ($varnishlog == true ) {

    service { "varnishlog-${instance}":
      enable  => true,
      ensure  => running,
      require => [
        File["/etc/init.d/varnishlog-${instance}"],
        Service["varnish-${instance}"],
      ],
    }

  } else {

    service { "varnishlog-${instance}":
      enable  => false,
      ensure  => stopped,
      require => File["/etc/init.d/varnishlog-${instance}"],
    }
  }

}
