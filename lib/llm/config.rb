require 'ruby_llm'

module Llm::Config
  DEFAULT_MODEL = 'gpt-4.1-mini'.freeze

  # Providers known to be "local" / self-hosted — they don't require API keys
  # and auto-force assume_model_exists in RubyLLM
  LOCAL_PROVIDERS = %w[ollama gpustack].freeze

  class << self
    def initialized?
      @initialized ||= false
    end

    def initialize!
      return if @initialized

      configure_ruby_llm
      @initialized = true
    end

    def reset!
      @initialized = false
    end

    def provider
      InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value.presence || 'openai'
    end

    def llm_api_base
      InstallationConfig.find_by(name: 'CAPTAIN_LLM_API_BASE')&.value.presence
    end

    def llm_api_key
      InstallationConfig.find_by(name: 'CAPTAIN_LLM_API_KEY')&.value
    end

    def embedding_dimensions
      InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_DIMENSIONS')&.value || 1536
    end

    def local_provider?
      LOCAL_PROVIDERS.include?(provider) || !RubyLLM::Provider.providers.key?(provider.to_sym)
    end

    # Returns chat params with correct provider routing.
    # For models from the active provider: pass provider: + assume_model_exists.
    # For models from known cloud providers: just model name (RubyLLM auto-detects).
    # For custom/unknown providers: route via OpenAI-compatible endpoint.
    def chat_params_for(model_name)
      active = provider
      model_config = Llm::Models.models[model_name.to_s]
      model_provider = model_config&.dig('provider')

      if model_provider == active || (local_provider? && model_config.nil?)
        ruby_llm_provider = resolve_ruby_llm_provider(active)
        { model: model_name, provider: ruby_llm_provider, assume_model_exists: true }
      elsif model_provider == 'self_hosted'
        # Self-hosted models route through the active provider
        ruby_llm_provider = resolve_ruby_llm_provider(active)
        { model: model_name, provider: ruby_llm_provider, assume_model_exists: true }
      else
        { model: model_name }
      end
    end

    # Maps our provider name to the RubyLLM provider symbol.
    # Known RubyLLM providers map directly; unknown ones route via :openai.
    def resolve_ruby_llm_provider(provider_name)
      sym = provider_name.to_sym
      return sym if RubyLLM::Provider.providers.key?(sym)
      # Unknown provider → use OpenAI-compatible routing
      :openai
    end

    def with_api_key(api_key, api_base: nil)
      initialize!
      context = RubyLLM.context do |config|
        config.openai_api_key = api_key
        config.openai_api_base = api_base
        configure_active_provider(config)
      end

      yield context
    end

    private

    def configure_ruby_llm
      RubyLLM.configure do |config|
        # Always configure OpenAI (backward compat + fallback for custom providers)
        config.openai_api_key = system_api_key if system_api_key.present?
        config.openai_api_base = openai_endpoint.chomp('/') if openai_endpoint.present?

        # Dynamically configure the active provider
        configure_active_provider(config)

        config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
        config.logger = Rails.logger
      end
    end

    # Dynamically configures any RubyLLM-supported provider.
    # For known providers (ollama, deepseek, etc.), sets their native config.
    # For unknown providers (custom), sets openai_api_base for OpenAI-compat routing.
    def configure_active_provider(config)
      active = provider.to_sym
      base = llm_api_base
      key = llm_api_key

      if RubyLLM::Provider.providers.key?(active)
        # Known RubyLLM provider — set its native config dynamically
        api_key_method = :"#{active}_api_key"
        api_base_method = :"#{active}_api_base"

        config.send(api_key_method, key) if key.present? && config.respond_to?(api_key_method)
        config.send(api_base_method, base.chomp('/')) if base.present? && config.respond_to?(api_base_method)
      elsif base.present?
        # Unknown provider (custom OpenAI-compatible) — route via OpenAI
        config.openai_api_key = key || 'dummy-key'
        config.openai_api_base = base.chomp('/')
      end
    end

    def system_api_key
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    end

    def openai_endpoint
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    end
  end
end