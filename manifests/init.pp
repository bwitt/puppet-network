# @summary Install the packages and gems required by the network_route and network_config resources
#
# @param ifupdown_extra
#   The name of the ifupdown-extra package
# @param ifupdown_extra_provider
#   The provider of the ifupdown-extra package
# @param manage_ifupdown_extra
#   Whether this class should manage the ifupdown-extra package
# @param ensure_ifupdown_extra
#   What state the ifupdown-extra package should be in
# @param ipaddress
#   The name of the ipaddress gems
# @param ipaddress_provider
#   The provider of the ipaddress gem
# @param manage_ipaddress
#   Whether this class should manage the ipaddress gem
# @param ensure_ipaddress
#   What state the ipaddress package should be in
# @param manage_networkmanager
#   Whether this class should manage the NetworkManager package
# @param networkmanager_package
#   The name of the NetworkManager package
# @param ensure_networkmanager
#   What state the NetworkManager package should be in
# @param manage_networkmanager_service
#   Whether this class should manage the NetworkManager service
# @param networkmanager_service
#   The name of the NetworkManager service
# @param ensure_networkmanager_service
#   What state the NetworkManager service should be in
# @param enable_networkmanager_service
#   Whether the NetworkManager service should be enabled at boot
#
class network (
  String[1]               $ifupdown_extra          = 'ifupdown-extra',
  Optional[String[1]]     $ifupdown_extra_provider = undef,
  Boolean                 $manage_ifupdown_extra   = true,
  Stdlib::Ensure::Package $ensure_ifupdown_extra   = present,
  String[1]               $ipaddress               = 'ipaddress',
  String[1]               $ipaddress_provider      = 'puppet_gem',
  Boolean                 $manage_ipaddress        = true,
  Stdlib::Ensure::Package $ensure_ipaddress        = absent,
  Boolean                 $manage_networkmanager   = false,
  String[1]               $networkmanager_package  = $facts['os']['family'] ? {
    'Debian' => 'network-manager',
    default  => 'NetworkManager',
  },
  Stdlib::Ensure::Package $ensure_networkmanager   = present,
  Boolean                 $manage_networkmanager_service = false,
  String[1]               $networkmanager_service  = 'NetworkManager',
  Enum['running', 'stopped'] $ensure_networkmanager_service = running,
  Boolean                 $enable_networkmanager_service = true,
) {
  if $facts['os']['family'] == 'Debian' and $manage_ifupdown_extra {
    package { $ifupdown_extra:
      ensure   => $ensure_ifupdown_extra,
      provider => $ifupdown_extra_provider,
    }
    Package[$ifupdown_extra] -> Network_route <| |>
  }

  if $manage_ipaddress {
    package { $ipaddress:
      ensure   => $ensure_ipaddress,
      provider => $ipaddress_provider,
    }
    Package[$ipaddress] -> Network_config <| |>
  }

  if $manage_networkmanager {
    package { $networkmanager_package:
      ensure => $ensure_networkmanager,
    }
    Package[$networkmanager_package] -> Network_config <| |>
    Package[$networkmanager_package] -> Network_route <| |>
  }

  if $manage_networkmanager_service {
    service { $networkmanager_service:
      ensure => $ensure_networkmanager_service,
      enable => $enable_networkmanager_service,
    }
    Service[$networkmanager_service] -> Network_config <| |>
    Service[$networkmanager_service] -> Network_route <| |>
  }

  if $manage_networkmanager and $manage_networkmanager_service {
    Package[$networkmanager_package] -> Service[$networkmanager_service]
  }
}
