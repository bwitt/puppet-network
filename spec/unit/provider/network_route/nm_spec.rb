require 'spec_helper'

describe Puppet::Type.type(:network_route).provider(:nm) do
  let(:nmcli_output) do
    <<~'OUTPUT'
      eth0:0.0.0.0/0 192.0.2.1 100, 203.0.113.0/24 192.0.2.254 150:2001\:db8\:1\:\:/64 2001\:db8\:\:1 200
    OUTPUT
  end

  describe '.instances' do
    before do
      allow(described_class).to receive(:nmcli).with('-t', '-f', described_class.route_fields.join(','), 'connection', 'show').and_return(nmcli_output)
    end

    it 'parses default routes' do
      default_route = described_class.instances.find { |route| route.name == 'default' }

      expect(default_route.network).to eq('default')
      expect(default_route.netmask).to eq('0.0.0.0')
      expect(default_route.gateway).to eq('192.0.2.1')
      expect(default_route.interface).to eq('eth0')
      expect(default_route.options).to eq('metric=100')
    end

    it 'parses ipv4 routes' do
      route = described_class.instances.find { |instance| instance.name == '203.0.113.0/24' }

      expect(route.network).to eq('203.0.113.0')
      expect(route.netmask).to eq('255.255.255.0')
      expect(route.gateway).to eq('192.0.2.254')
      expect(route.options).to eq('metric=150')
    end

    it 'parses ipv6 routes' do
      route = described_class.instances.find { |instance| instance.name == '2001:db8:1::/64' }

      expect(route.network).to eq('2001:db8:1::')
      expect(route.gateway).to eq('2001:db8::1')
      expect(route.options).to eq('metric=200')
    end
  end

  describe '#add_route' do
    let(:resource) do
      Puppet::Type.type(:network_route).new(
        name: '203.0.113.0/24',
        provider: :nm,
        network: '203.0.113.0',
        netmask: '255.255.255.0',
        gateway: '192.0.2.254',
        interface: 'eth0',
        options: 'metric=150',
      )
    end
    let(:provider) { described_class.new(resource) }

    it 'adds route to the owning connection' do
      expect(provider).to receive(:nmcli).with('connection', 'modify', 'eth0', '+ipv4.routes', '203.0.113.0/24 192.0.2.254 150')

      provider.add_route
    end
  end

  describe '#destination' do
    let(:resource) do
      Puppet::Type.type(:network_route).new(
        name: 'default',
        provider: :nm,
        network: 'default',
        netmask: '0.0.0.0',
        gateway: '192.0.2.1',
        interface: 'eth0',
      )
    end

    it 'builds default route destinations' do
      expect(described_class.new(resource).destination).to eq('0.0.0.0/0')
    end
  end
end
