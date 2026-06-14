# frozen_string_literal: true

require 'agents'

Rails.application.config.after_initialize do
  api_key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  model = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
  api_endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value || LlmConstants::OPENAI_API_ENDPOINT
  llm_provider = InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value || 'openai'
  llm_api_base = InstallationConfig.find_by(name: 'CAPTAIN_LLM_API_BASE')&.value
  llm_api_key = InstallationConfig.find_by(name: 'CAPTAIN_LLM_API_KEY')&.value

  # The ai-agents SDK uses the OpenAI-compatible API.
  # For any non-OpenAI provider, point openai_api_base to the provider's endpoint.
  if llm_provider != 'openai' && llm_api_base.present?
    Agents.configure do |config|
      config.openai_api_key = llm_api_key || 'dummy-key'
      config.openai_api_base = "#{llm_api_base.chomp('/')}/v1"
      config.default_model = model
      config.debug = false
    end
  elsif api_key.present?
    Agents.configure do |config|
      config.openai_api_key = api_key
      if api_endpoint.present?
        api_base = "#{api_endpoint.chomp('/')}/v1"
        config.openai_api_base = api_base
      end
      config.default_model = model
      config.debug = false
    end
  end
rescue StandardError => e
  Rails.logger.error "Failed to configure AI Agents SDK: #{e.message}"
end