require 'ipaddr'

module Puppet
  class Provider
    module NetworkManager
      module_function

      def split_escaped(value, separator = ':')
        fields = []
        field = +''
        escaped = false

        value.to_s.each_char do |char|
          if escaped
            field << char
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == separator
            fields << field
            field = +''
          else
            field << char
          end
        end

        fields << field
      end

      def parse_table(output, fields)
        output.to_s.lines.map(&:chomp).reject(&:empty?).map do |line|
          values = split_escaped(line)
          fields.zip(values).each_with_object({}) do |(field, value), hash|
            hash[field] = blank_value?(value) ? nil : value
          end
        end
      end

      def blank_value?(value)
        value.nil? || value.empty? || value == '--'
      end

      def nm_bool(value)
        return nil if value.nil? || value == :absent

        [true, :true, 'true', 'yes', '1'].include?(value)
      end

      def nm_yes_no(value)
        nm_bool(value) ? 'yes' : 'no'
      end

      def prefix_to_netmask(prefix_length)
        prefix = prefix_length.to_i
        mask = (0xffffffff << (32 - prefix)) & 0xffffffff

        [24, 16, 8, 0].map { |shift| (mask >> shift) & 0xff }.join('.')
      end

      def netmask_to_prefix(netmask)
        return nil if blank_value?(netmask)
        return netmask.to_i if netmask.to_s.match?(%r{\A\d{1,3}\z})

        IPAddr.new(netmask).to_i.to_s(2).count('1')
      end

      def address_family(address)
        IPAddr.new(address).ipv6? ? 'ipv6' : 'ipv4'
      end

      def route_destination(network, netmask, gateway = nil)
        if network == 'default'
          return '::/0' if gateway && IPAddr.new(gateway).ipv6?

          return '0.0.0.0/0'
        end

        ip = IPAddr.new(network)
        prefix = ip.ipv4? ? netmask_to_prefix(netmask) : netmask.to_s.to_i

        "#{ip}/#{prefix}"
      end

      def route_hash(destination)
        if ['0.0.0.0/0', '::/0'].include?(destination)
          return {
            name: 'default',
            network: 'default',
            netmask: destination.include?(':') ? '0' : '0.0.0.0',
          }
        end

        ip = IPAddr.new(destination)
        prefix = destination.split('/')[1]
        netmask = ip.ipv4? ? prefix_to_netmask(prefix) : IPAddr.new('ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff').mask(prefix.to_i).to_s

        {
          name: "#{ip}/#{prefix}",
          network: ip.to_s,
          netmask: netmask,
        }
      end

      def flatten_options(options, excluded_keys = [])
        return [] if options.nil? || options == :absent

        options.each_with_object([]) do |(key, value), settings|
          key = key.to_s
          next if excluded_keys.include?(key)

          if value.is_a?(Hash)
            value.each_pair do |nested_key, nested_value|
              settings << ["#{key}.#{nested_key}", nested_value.to_s]
            end
          elsif key.include?('.')
            settings << [key, value.to_s]
          end
        end
      end
    end
  end
end
