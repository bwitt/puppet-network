require_relative '../networkmanager'

Puppet::Type.type(:network_config).provide(:nm) do
  desc 'NetworkManager connection provider using nmcli'

  commands nmcli: 'nmcli'

  has_feature :provider_options
  has_feature :hotpluggable
  has_feature :reconfigurable

  def self.nm
    Puppet::Provider::NetworkManager
  end

  def self.connection_fields
    [
      'NAME',
      'TYPE',
      'DEVICE',
      'AUTOCONNECT',
      'ipv4.method',
      'ipv4.addresses',
      'ipv6.method',
      'ipv6.addresses',
      '802-3-ethernet.mtu',
      'vlan.parent',
      'vlan.id',
    ]
  end

  def self.instances
    output = nmcli('-t', '-f', connection_fields.join(','), 'connection', 'show')

    nm.parse_table(output, connection_fields).map do |connection|
      new(connection_to_hash(connection))
    end
  rescue Puppet::ExecutionFailure => e
    Puppet.debug("Failed to list NetworkManager connections: #{e.message}")
    []
  end

  def self.prefetch(resources)
    instances.each do |instance|
      if (resource = resources[instance.name])
        resource.provider = instance
      end
    end
  end

  def self.connection_to_hash(connection)
    family = (connection['ipv6.method'] && connection['ipv6.method'] != 'disabled') ? :inet6 : :inet
    method = nm_method(connection, family)
    address = first_address(connection[(family == :inet6) ? 'ipv6.addresses' : 'ipv4.addresses'])

    hash = {
      ensure: :present,
      name: connection['NAME'],
      provider: :nm,
      family: family,
      method: method,
      onboot: connection['AUTOCONNECT'] != 'no',
      hotplug: true,
      mode: (connection['TYPE'] == 'vlan') ? :vlan : :raw,
      options: connection_options(connection),
    }

    if address && method == :static
      ip, prefix = address.split('/', 2)
      hash[:ipaddress] = ip
      hash[:netmask] = (family == :inet6) ? prefix : nm.prefix_to_netmask(prefix)
    end

    hash[:mtu] = connection['802-3-ethernet.mtu'] if connection['802-3-ethernet.mtu']
    hash
  end

  def self.nm_method(connection, family)
    method = connection[(family == :inet6) ? 'ipv6.method' : 'ipv4.method']

    case method
    when 'auto'
      :dhcp
    when 'manual'
      if first_address(connection[(family == :inet6) ? 'ipv6.addresses' : 'ipv4.addresses'])
        :static
      else
        :manual
      end
    else
      :manual
    end
  end

  def self.first_address(addresses)
    return nil if nm.blank_value?(addresses)

    addresses.split(',').first
  end

  def self.connection_options(connection)
    options = {}
    options['connection.interface-name'] = connection['DEVICE'] if connection['DEVICE']
    options['vlan.parent'] = connection['vlan.parent'] if connection['vlan.parent']
    options['vlan.id'] = connection['vlan.id'] if connection['vlan.id']
    options
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    add_connection
    @property_hash[:ensure] = :present
    apply_config
  end

  def destroy
    nmcli('connection', 'delete', @resource[:name])
    @property_hash.clear
  end

  def flush
    return unless @property_hash[:ensure] == :present

    apply_config
  end

  def add_connection
    if connection_type == 'vlan'
      nmcli('connection', 'add', 'type', 'vlan', 'con-name', @resource[:name], 'ifname', interface_name, 'dev', vlan_parent, 'id', vlan_id)
    else
      nmcli('connection', 'add', 'type', connection_type, 'con-name', @resource[:name], 'ifname', interface_name)
    end
  end

  def apply_config
    settings = build_modify_settings
    nmcli('connection', 'modify', @resource[:name], *settings.flatten) unless settings.empty?
    nmcli('connection', 'up', @resource[:name]) if nm.nm_bool(@resource[:reconfigure])
  end

  def build_modify_settings
    settings = []
    settings << ['connection.autoconnect', nm.nm_yes_no(@resource[:onboot])]

    settings << ['802-3-ethernet.mtu', @resource[:mtu].to_s] if @resource[:mtu] && connection_type == 'ethernet'

    settings.concat(ip_settings)
    settings.concat(nm.flatten_options(@resource[:options], reserved_option_keys))
    settings
  end

  def ip_settings
    family = (@resource[:family] == :inet6) ? 'ipv6' : 'ipv4'
    other_family = (family == 'ipv6') ? 'ipv4' : 'ipv6'
    settings = [["#{other_family}.method", 'disabled']]

    case @resource[:method]
    when :dhcp
      settings << ["#{family}.method", 'auto']
    when :static
      settings << ["#{family}.method", 'manual']
      settings << ["#{family}.addresses", address_with_prefix(family)]
    else
      settings << ["#{family}.method", 'disabled']
    end

    gateway = option_value("#{family}.gateway") || option_value('gateway')
    settings << ["#{family}.gateway", gateway] if gateway
    settings
  end

  def address_with_prefix(family)
    prefix = (family == 'ipv6') ? @resource[:netmask].to_s : nm.netmask_to_prefix(@resource[:netmask])
    "#{@resource[:ipaddress]}/#{prefix}"
  end

  def connection_type
    option_value('connection.type') || ((@resource[:mode] == :vlan) ? 'vlan' : 'ethernet')
  end

  def interface_name
    option_value('connection.interface-name') || option_value('interface-name') || @resource[:name]
  end

  def vlan_parent
    option_value('vlan.parent') || interface_name.split('.').first
  end

  def vlan_id
    option_value('vlan.id') || interface_name.split('.').last
  end

  def option_value(key)
    options = @resource[:options]
    return nil if options.nil? || options == :absent

    options[key]
  end

  def reserved_option_keys
    %w[connection.type connection.interface-name interface-name vlan.parent vlan.id gateway ipv4.gateway ipv6.gateway]
  end

  def nm
    self.class.nm
  end

  %i[onboot method ipaddress netmask family mtu hotplug options mode].each do |property|
    define_method(property) do
      @property_hash[property]
    end

    define_method("#{property}=") do |value|
      @property_hash[property] = value
    end
  end
end
