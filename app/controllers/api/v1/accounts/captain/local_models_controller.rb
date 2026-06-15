# frozen_string_literal: true

class Api::V1::Accounts::Captain::LocalModelsController < Api::V1::Accounts::BaseController
  before_action :current_account

  def index
    # Use the embedding API base when discovering models for embedding purposes
    api_base = if params[:purpose] == 'embedding'
                 Llm::Config.embedding_api_base
               else
                 Llm::Config.llm_api_base
               end

    return render json: { models: [], error: 'LLM API base URL not configured' } unless api_base.present?

    models = discover_models(api_base)
    models = filter_models_by_purpose(models, params[:purpose]) if params[:purpose].present?
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
        embedding_dimensions: model_config&.dig('embedding_dimensions'),
        type: model_config&.dig('type') || guess_model_type(model_name, m)
      }.compact
    end
  end

  def filter_models_by_purpose(models, purpose)
    case purpose
    when 'embedding'
      # Return models that are known embedding models or have embedding_dimensions
      known_embedding_ids = Llm::Models.embedding_models.keys
      models.select do |m|
        known_embedding_ids.include?(m[:id]) || m[:embedding_dimensions].present? || m[:type] == 'embedding'
      end
    when 'chat'
      # Return models that are NOT embedding-only models
      known_embedding_ids = Llm::Models.embedding_models.keys
      models.reject { |m| known_embedding_ids.include?(m[:id]) || m[:type] == 'embedding' }
    else
      models
    end
  end

  # Guess model type from Ollama model metadata when not in our registry
  def guess_model_type(model_name, model_data)
    # Ollama models often include family info that helps distinguish
    family = model_data.dig('details', 'family')
    return 'embedding' if family&.include?('embed')
    # Known embedding model name patterns
    return 'embedding' if model_name.match?(/embed|e5|bge-/)

    nil
  end
end