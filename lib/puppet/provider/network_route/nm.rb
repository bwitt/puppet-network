require_relative '../networkmanager'

Puppet::Type.type(:network_route).provide(:nm) do
  desc 'NetworkManager route provider using nmcli'

  commands nmcli: 'nmcli'

  has_feature :provider_options

  def self.nm
    Puppet::Provider::NetworkManager
  end

  def self.route_fields
    ['NAME', 'ipv4.routes', 'ipv6.routes']
  end

  def self.instances
    output = nmcli('-t', '-f', route_fields.join(','), 'connection', 'show')

    nm.parse_table(output, route_fields).flat_map do |connection|
      routes_from_connection(connection)
    end
  rescue Puppet::ExecutionFailure => e
    Puppet.debug("Failed to list NetworkManager routes: #{e.message}")
    []
  end

  def self.prefetch(resources)
    instances.each do |instance|
      if (resource = resources[instance.name])
        resource.provider = instance
      end
    end
  end

  def self.routes_from_connection(connection)
    routes = []
    routes.concat(parse_routes(connection['NAME'], connection['ipv4.routes']))
    routes.concat(parse_routes(connection['NAME'], connection['ipv6.routes']))
    routes.map { |route| new(route) }
  end

  def self.parse_routes(connection_name, routes)
    return [] if nm.blank_value?(routes)

    routes.split(',').filter_map do |route|
      destination, gateway, metric = route.split
      next unless destination && gateway

      hash = nm.route_hash(destination)
      hash.merge(
        ensure: :present,
        provider: :nm,
        gateway: gateway,
        interface: connection_name,
        options: metric ? "metric=#{metric}" : nil,
      )
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    @property_hash[:ensure] = :present
    add_route
  end

  def destroy
    remove_route
    @property_hash.clear
  end

  def flush
    return unless @property_hash[:ensure] == :present

    remove_route if exists?
    add_route
  end

  def add_route
    nmcli('connection', 'modify', @resource[:interface], "+#{route_family}.routes", route_value)
  end

  def remove_route
    nmcli('connection', 'modify', @resource[:interface], "-#{route_family}.routes", route_value)
  end

  def route_family
    nm.address_family(destination.split('/').first)
  end

  def route_value
    [destination, @resource[:gateway], route_metric].compact.join(' ')
  end

  def destination
    raise Puppet::Error, 'NetworkManager provider does not support local routes' if @resource[:network] == 'local'

    nm.route_destination(@resource[:network], @resource[:netmask], @resource[:gateway])
  end

  def route_metric
    return nil if @resource[:options].nil? || @resource[:options] == :absent

    match = @resource[:options].match(%r{(?:\A|\s)metric(?:=|\s+)(\d+)(?:\s|\z)})
    match[1] if match
  end

  def nm
    self.class.nm
  end

  %i[network netmask gateway interface options].each do |property|
    define_method(property) do
      @property_hash[property]
    end

    define_method("#{property}=") do |value|
      @property_hash[property] = value
    end
  end
end
