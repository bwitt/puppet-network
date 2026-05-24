require 'spec_helper'

describe 'network' do
  on_supported_os.each do |os, facts|
    context "on #{os}" do
      let(:facts) { facts }

      context 'with default parameters' do
        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_package('NetworkManager') }
        it { is_expected.not_to contain_service('NetworkManager') }
      end

      context 'when managing NetworkManager' do
        let(:params) do
          {
            manage_networkmanager: true,
            manage_networkmanager_service: true,
          }
        end

        it { is_expected.to contain_package((facts[:os]['family'] == 'Debian') ? 'network-manager' : 'NetworkManager').with_ensure('present') }
        it { is_expected.to contain_service('NetworkManager').with_ensure('running').with_enable(true) }
      end
    end
  end
end
