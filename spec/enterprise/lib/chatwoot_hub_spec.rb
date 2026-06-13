require 'rails_helper'

RSpec.describe ChatwootHub do
  describe '.base_url' do
    it 'uses the static hub url outside development for enterprise edition' do
      with_modified_env CHATWOOT_HUB_URL: 'https://custom.example.com' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

        expect(described_class.base_url).to eq('https://hub.2.chatwoot.com')
      end
    end

    it 'uses CHATWOOT_HUB_URL in development for enterprise edition' do
      with_modified_env CHATWOOT_HUB_URL: 'https://custom.example.com' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))

        expect(described_class.base_url).to eq('https://custom.example.com')
      end
    end
  end

  describe '.sync_with_hub' do
    context 'when self-hosted enterprise' do
      before do
        allow(ChatwootApp).to receive(:self_hosted_enterprise?).and_return(true)
      end

      it 'returns an empty hash without making a network call' do
        allow(RestClient).to receive(:post)
        expect(described_class.sync_with_hub).to eq({})
        expect(RestClient).not_to have_received(:post)
      end
    end

    context 'when not self-hosted enterprise' do
      before do
        allow(ChatwootApp).to receive(:self_hosted_enterprise?).and_return(false)
      end

      it 'makes the network call' do
        allow(RestClient).to receive(:post).and_return({ version: '1.1.1' }.to_json)
        expect(described_class.sync_with_hub['version']).to eq('1.1.1')
        expect(RestClient).to have_received(:post)
      end
    end
  end

  describe '.register_instance' do
    context 'when self-hosted enterprise' do
      before do
        allow(ChatwootApp).to receive(:self_hosted_enterprise?).and_return(true)
      end

      it 'does not make a network call' do
        allow(RestClient).to receive(:post)
        described_class.register_instance('Test', 'Admin', 'admin@test.com')
        expect(RestClient).not_to have_received(:post)
      end
    end

    context 'when not self-hosted enterprise' do
      before do
        allow(ChatwootApp).to receive(:self_hosted_enterprise?).and_return(false)
      end

      it 'makes the network call' do
        allow(RestClient).to receive(:post)
        described_class.register_instance('Test', 'Admin', 'admin@test.com')
        expect(RestClient).to have_received(:post)
      end
    end
  end

  describe '.send_push' do
    context 'when self-hosted enterprise' do
      before do
        allow(ChatwootApp).to receive(:self_hosted_enterprise?).and_return(true)
      end

      it 'does not make a network call' do
        allow(RestClient).to receive(:post)
        described_class.send_push({ token: 'test' })
        expect(RestClient).not_to have_received(:post)
      end
    end

    context 'when not self-hosted enterprise' do
      before do
        allow(ChatwootApp).to receive(:self_hosted_enterprise?).and_return(false)
      end

      it 'makes the network call' do
        allow(RestClient).to receive(:post)
        described_class.send_push({ token: 'test' })
        expect(RestClient).to have_received(:post)
      end
    end
  end

  describe '.send_push_with_response' do
    context 'when self-hosted enterprise' do
      before do
        allow(ChatwootApp).to receive(:self_hosted_enterprise?).and_return(true)
      end

      it 'returns nil without making a network call' do
        allow(RestClient).to receive(:post)
        expect(described_class.send_push_with_response({ token: 'test' })).to be_nil
        expect(RestClient).not_to have_received(:post)
      end
    end

    context 'when not self-hosted enterprise' do
      before do
        allow(ChatwootApp).to receive(:self_hosted_enterprise?).and_return(false)
      end

      it 'makes the network call' do
        allow(RestClient).to receive(:post).and_return(double(code: 200, body: '{}'))
        described_class.send_push_with_response({ token: 'test' })
        expect(RestClient).to have_received(:post)
      end
    end
  end

  describe '.emit_event' do
    context 'when self-hosted enterprise' do
      before do
        allow(ChatwootApp).to receive(:self_hosted_enterprise?).and_return(true)
      end

      it 'does not make a network call regardless of DISABLE_TELEMETRY' do
        with_modified_env DISABLE_TELEMETRY: nil do
          allow(RestClient).to receive(:post)
          described_class.emit_event('test_event', { data: 'test' })
          expect(RestClient).not_to have_received(:post)
        end
      end
    end

    context 'when not self-hosted enterprise' do
      before do
        allow(ChatwootApp).to receive(:self_hosted_enterprise?).and_return(false)
      end

      it 'makes the network call when telemetry is enabled' do
        with_modified_env DISABLE_TELEMETRY: nil do
          allow(RestClient).to receive(:post)
          described_class.emit_event('test_event', { data: 'test' })
          expect(RestClient).to have_received(:post)
        end
      end

      it 'does not make the network call when DISABLE_TELEMETRY is set' do
        with_modified_env DISABLE_TELEMETRY: 'true' do
          allow(RestClient).to receive(:post)
          described_class.emit_event('test_event', { data: 'test' })
          expect(RestClient).not_to have_received(:post)
        end
      end
    end
  end
end
