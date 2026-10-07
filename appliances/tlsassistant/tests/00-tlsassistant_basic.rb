# Basic test for TLSAssistant appliance

require_relative '../../../lib/community/app_handler'

describe 'TLSAssistant appliance' do
  include_context('vm_handler')

  it 'docker engine is installed and running' do
    result = @info[:vm].ssh('systemctl is-active docker')
    expect(result.exitstatus).to eq(0)
    expect(result.stdout.strip).to eq('active')
  end

  it 'tlsassistant docker image is present' do
    result = @info[:vm].ssh("docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'stfbk/tlsassistant|ghcr.io/stfbk/tlsassistant'")
    expect(result.exitstatus).to eq(0)
  end
end
