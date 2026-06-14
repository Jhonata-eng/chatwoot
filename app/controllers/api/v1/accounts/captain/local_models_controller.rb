# frozen_string_literal: true

class Api::V1::Accounts::Captain::LocalModelsController < Api::V1::Accounts::BaseController
  before_action :current_account

  def index
    api_base = InstallationConfig.find_by(name: 'CAPTAIN_LLM_API_BASE')&.value

    return render json: { models: [], error: 'LLM API base URL not configured' } unless api_base.present?

    models = discover_models(api_base)
    render json: { models: models }
  rescue StandardError => e
    Rails.logger.error "Failed to discover local models: #{e.message}"
    render json: { models: [], error: e.message }
  end

  private

  def discover_models(base_url)
    # Tries /api/tags (Ollama) — works for most self-hosted providers.
    # Other endpoints can be added in the future.
    discover_ollama_models(base_url)
  end

  def discover_ollama_models(base_url)
    require 'net/http'
    require 'json'

    uri = URI("#{base_url.chomp('/')}/api/tags")
    response = Net::HTTP.get(uri)
    data = JSON.parse(response)

    data.fetch('models', []).map do |m|
      model_name = m['name']
      model_config = Llm::Models.models[model_name]

      {
        id: model_name,
        display_name: model_config&.dig('display_name') || model_name,
        provider: 'self_hosted',
        supports_tools: model_config&.dig('supports_tools'),
        embedding_dimensions: model_config&.dig('embedding_dimensions')
      }.compact
    end
  end
end