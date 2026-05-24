require 'spec_helper'

describe Puppet::Type.type(:network_config).provider(:nm) do
  let(:nmcli_output) do
    <<~OUTPUT
      eth0:ethernet:eth0:yes:manual:192.0.2.10/24:disabled:--:1500:--:--
      Wired connection 1:ethernet:enp1s0:no:auto:--:disabled:--:--:--:--
      vlan100:vlan:vlan100:yes:manual:198.51.100.2/24:disabled:--:--:eth0:100
    OUTPUT
  end

  describe '.instances' do
    before do
      allow(described_class).to receive(:nmcli).with('-t', '-f', described_class.connection_fields.join(','), 'connection', 'show').and_return(nmcli_output)
    end

    it 'parses static connections' do
      eth0 = described_class.instances.find { |instance| instance.name == 'eth0' }

      expect(eth0.method).to eq(:static)
      expect(eth0.ipaddress).to eq('192.0.2.10')
      expect(eth0.netmask).to eq('255.255.255.0')
      expect(eth0.mtu).to eq('1500')
      expect(eth0.onboot).to be(true)
    end

    it 'parses dhcp connections with separate connection names' do
      connection = described_class.instances.find { |instance| instance.name == 'Wired connection 1' }

      expect(connection.method).to eq(:dhcp)
      expect(connection.options).to eq('connection.interface-name' => 'enp1s0')
      expect(connection.onboot).to be(false)
    end

    it 'parses vlan connections' do
      vlan = described_class.instances.find { |instance| instance.name == 'vlan100' }

      expect(vlan.mode).to eq(:vlan)
      expect(vlan.options).to include('vlan.parent' => 'eth0', 'vlan.id' => '100')
    end
  end

  describe '#build_modify_settings' do
    let(:resource) do
      Puppet::Type.type(:network_config).new(
        name: 'eth0',
        provider: :nm,
        family: :inet,
        method: :static,
        ipaddress: '192.0.2.10',
        netmask: '255.255.255.0',
        onboot: true,
        mtu: '1500',
        options: { 'gateway' => '192.0.2.1', 'ipv4.dns' => '192.0.2.53' },
      )
    end
    let(:provider) { described_class.new(resource) }

    it 'builds nmcli settings for static ipv4' do
      expect(provider.build_modify_settings).to include(
        ['connection.autoconnect', 'yes'],
        ['802-3-ethernet.mtu', '1500'],
        ['ipv6.method', 'disabled'],
        ['ipv4.method', 'manual'],
        ['ipv4.addresses', '192.0.2.10/24'],
        ['ipv4.gateway', '192.0.2.1'],
        ['ipv4.dns', '192.0.2.53'],
      )
    end
  end

  describe '#add_connection' do
    let(:resource) do
      Puppet::Type.type(:network_config).new(
        name: 'vlan100',
        provider: :nm,
        mode: :vlan,
        options: { 'connection.interface-name' => 'eth0.100', 'vlan.parent' => 'eth0', 'vlan.id' => '100' },
      )
    end
    let(:provider) { described_class.new(resource) }

    it 'adds vlan connections with parent and id' do
      expect(provider).to receive(:nmcli).with('connection', 'add', 'type', 'vlan', 'con-name', 'vlan100', 'ifname', 'eth0.100', 'dev', 'eth0', 'id', '100')

      provider.add_connection
    end
  end
end
