
$binpath = "/usr/local/bin/:/bin/:/usr/bin:/usr/sbin:/usr/local/sbin:/sbin"

# assign ip to ivs internal port
define ivs_internal_port_ip {
    $port_ip = split($name, ',')
    file_line { "ifconfig ${port_ip[0]} up":
        path  => '/etc/rc.d/rc.local',
        line  => "ifconfig ${port_ip[0]} up",
        match => "^ifconfig ${port_ip[0]} up",
    }->
    file_line { "ip link set ${port_ip[0]} up":
        path  => '/etc/rc.d/rc.local',
        line  => "ip link set ${port_ip[0]} up",
        match => "^ip link set ${port_ip[0]} up",
    }->
    file_line { "ifconfig ${port_ip[0]} ${port_ip[1]}":
        path  => '/etc/rc.d/rc.local',
        line  => "ifconfig ${port_ip[0]} ${port_ip[1]}",
        match => "^ifconfig ${port_ip[0]} ${port_ip[1]}$",
    }
}
# example ['storage,192.168.1.1/24', 'ex,192.168.2.1/24', 'management,192.168.3.1/24']
class ivs_internal_port_ips {
    $port_ips = [%(port_ips)s]
    $default_gw = "%(default_gw)s"
    file { "/etc/rc.d/rc.local":
        ensure  => file,
        mode    => 0777,
    }->
    file_line { "restart ivs":
        require => File['/etc/rc.d/rc.local'],
        path    => '/etc/rc.d/rc.local',
        line    => "systemctl restart ivs",
        match   => "^systemctl restart ivs$",
    }->
    ivs_internal_port_ip { $port_ips:
    }->
    file_line { "clear default gw":
        path    => '/etc/rc.d/rc.local',
        line    => "ip route del default",
        match   => "^ip route del default$",
    }->
    file_line { "add default gw":
        path    => '/etc/rc.d/rc.local',
        line    => "ip route add default via ${default_gw}",
        match   => "^ip route add default via ${default_gw}$",
    }
}
include ivs_internal_port_ips

# TODO install selinux policies
#Package { allow_virtual => true }
#class { selinux:
#  mode => '%(selinux_mode)s'
#}
#selinux::module { 'selinux-bcf':
#  ensure => 'present',
#  source => 'puppet:///modules/selinux/centos.te',
#}

# install and enable ntp
package { "ntp":
    ensure  => installed,
}
service { "ntpd":
    ensure  => running,
    enable  => true,
    path    => $binpath,
    require => Package['ntp'],
}

# ivs configruation and service
file{'/etc/sysconfig/ivs':
    ensure  => file,
    mode    => 0644,
    content => "%(ivs_daemon_args)s",
    notify  => Service['ivs'],
} 
service{'ivs':
    ensure  => running,
    enable  => true,
    path    => $binpath,
}

# fix centos symbolic link problem for ivs debug logging
file { '/usr/lib64/debug':
   ensure => link,
   target => '/lib/debug',
}

# load 8021q module on boot
file {'/etc/sysconfig/modules/8021q.modules':
    ensure  => file,
    mode    => 0777,
    content => "modprobe 8021q",
}
exec { "load 8021q":
    command => "modprobe 8021q",
    path    => $binpath,
}

# config /etc/neutron/neutron.conf
ini_setting { "neutron.conf report_interval":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'agent',
  key_val_separator => '=',
  setting           => 'report_interval',
  value             => '60',
}
ini_setting { "neutron.conf agent_down_time":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'agent_down_time',
  value             => '150',
}
ini_setting { "neutron.conf service_plugins":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'service_plugins',
  value             => 'bsn_l3,lbaas',
}
ini_setting { "neutron.conf dhcp_agents_per_network":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'dhcp_agents_per_network',
  value             => '2',
}
ini_setting { "neutron.conf notification driver":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'notification_driver',
  value             => 'messaging',
}
ini_setting { "ensure absent of neutron.conf service providers":
  ensure            => absent,
  path              => '/etc/neutron/neutron.conf',
  section           => 'service_providers',
  key_val_separator => '=',
  setting           => 'service_provider',
}->
ini_setting { "neutron.conf service providers":
  ensure            => present,
  path              => '/etc/neutron/neutron.conf',
  section           => 'service_providers',
  key_val_separator => '=',
  setting           => 'service_provider',
  value             => 'LOADBALANCER:Haproxy:neutron.services.loadbalancer.drivers.haproxy.plugin_driver.HaproxyOnHostPluginDriver:default',
}

# config neutron-bsn-agent service
ini_setting { "neutron-bsn-agent.service Description":
  ensure            => present,
  path              => '/usr/lib/systemd/system/neutron-bsn-agent.service',
  section           => 'Unit',
  key_val_separator => '=',
  setting           => 'Description',
  value             => 'OpenStack Neutron BSN Agent',
}
ini_setting { "neutron-bsn-agent.service ExecStart":
  notify            => File['/etc/systemd/system/multi-user.target.wants/neutron-bsn-agent.service'],
  ensure            => present,
  path              => '/usr/lib/systemd/system/neutron-bsn-agent.service',
  section           => 'Service',
  key_val_separator => '=',
  setting           => 'ExecStart',
  value             => '/usr/bin/neutron-bsn-agent --config-file /usr/share/neutron/neutron-dist.conf --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/openvswitch/ovs_neutron_plugin.ini --log-file /var/log/neutron/neutron-bsn-agent.log',
}
file { '/etc/systemd/system/multi-user.target.wants/neutron-bsn-agent.service':
   ensure => link,
   target => '/usr/lib/systemd/system/neutron-bsn-agent.service',
   notify => Service['neutron-bsn-agent'],
}
service{'neutron-bsn-agent':
    ensure  => running,
    enable  => true,
    path    => $binpath,
}

# stop and disable neutron-openvswitch-agent
service { 'neutron-openvswitch-agent':
  ensure  => stopped,
  enable  => false,
  path    => $binpath,
}

# patch for packstack nova
package { "device-mapper-libs":
  ensure => latest,
  notify => Service['libvirtd'],
}
service { "libvirtd":
  ensure  => running,
  enable  => true,
  path    => $binpath,
  notify  => Service['openstack-nova-compute'],
}
service { "openstack-nova-compute":
  ensure  => running,
  enable  => true,
  path    => $binpath,
}

# disable l3 agent
ini_setting { "l3 agent disable metadata proxy":
  ensure            => present,
  path              => '/etc/neutron/l3_agent.ini',
  section           => 'DEFAULT',
  key_val_separator => '=',
  setting           => 'enable_metadata_proxy',
  value             => 'False',
}
file { '/etc/neutron/dnsmasq-neutron.conf':
  ensure            => file,
  content           => 'dhcp-option-force=26,1400',
}

# dhcp configuration
if %(deploy_dhcp_agent)s {
    ini_setting { "dhcp agent interface driver":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'interface_driver',
        value             => 'neutron.agent.linux.interface.IVSInterfaceDriver',
    }
    ini_setting { "dhcp agent dhcp driver":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'dhcp_driver',
        value             => 'bsnstacklib.plugins.bigswitch.dhcp_driver.DnsmasqWithMetaData',
    }
    ini_setting { "dhcp agent enable isolated metadata":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'enable_isolated_metadata',
        value             => 'True',
    }
    ini_setting { "dhcp agent disable metadata network":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'enable_metadata_network',
        value             => 'False',
    }
    ini_setting { "dhcp agent disable dhcp_delete_namespaces":
        ensure            => present,
        path              => '/etc/neutron/dhcp_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'dhcp_delete_namespaces',
        value             => 'False',
    }
}

# haproxy
if %(deploy_haproxy)s {
    package { "haproxy":
        ensure  => installed,
    }
    package { "keepalived":
        ensure  => installed,
    }
    ini_setting { "haproxy agent periodic interval":
        ensure            => present,
        path              => '/etc/neutron/lbaas_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'periodic_interval',
        value             => '10',
        notify            => Service['neutron-lbaas-agent'],
    }
    ini_setting { "haproxy agent interface driver":
        ensure            => present,
        path              => '/etc/neutron/lbaas_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'interface_driver',
        value             => 'neutron.agent.linux.interface.IVSInterfaceDriver',
        notify            => Service['neutron-lbaas-agent'],
    }
    ini_setting { "haproxy agent device driver":
        ensure            => present,
        path              => '/etc/neutron/lbaas_agent.ini',
        section           => 'DEFAULT',
        key_val_separator => '=',
        setting           => 'device_driver',
        value             => 'neutron.services.loadbalancer.drivers.haproxy.namespace_driver.HaproxyNSDriver',
        notify            => Service['neutron-lbaas-agent'],
    }
    service { "haproxy":
        ensure            => running,
        enable            => true,
        require           => Package['haproxy'],
    }
    service { "neutron-lbaas-agent":
        ensure            => running,
        enable            => true,
        require           => Package['haproxy'],
    }
    service { "keepalived":
        ensure            => running,
        enable            => true,
        require           => Package['keepalived'],
    }
    file_line { "net.ipv4.ip_nonlocal_bind=1":
        path  => '/etc/sysctl.conf',
        line  => "net.ipv4.ip_nonlocal_bind=1",
        match => "^net.ipv4.ip_nonlocal_bind=1",
    }
}

