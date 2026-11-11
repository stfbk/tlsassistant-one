# Basic test for TLSAssistant appliance

require_relative '../../../lib/community/app_handler'

describe 'TLSAssistant appliance' do
  include_context('vm_handler')

  it 'docker engine is installed and running' do
    # docker can still be starting when SSH becomes reachable
    @info[:vm].ssh("timeout 60 sh -c 'until systemctl -q is-active docker; do sleep 2; done'")
    result = @info[:vm].ssh('systemctl is-active docker')
    expect(result.exitstatus).to eq(0)
    expect(result.stdout.strip).to eq('active')
  end

  it 'tlsassistant docker image is present' do
    result = @info[:vm].ssh("docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'stfbk/tlsassistant|ghcr.io/stfbk/tlsassistant'")
    expect(result.exitstatus).to eq(0)
  end
end
