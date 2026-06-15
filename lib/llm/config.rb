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

    # Embedding-specific provider configuration.
    # Falls back to the chat provider when not explicitly set.
    def embedding_provider
      InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_PROVIDER')&.value.presence || provider
    end

    def embedding_api_base
      InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_API_BASE')&.value.presence || llm_api_base
    end

    def embedding_api_key
      InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_API_KEY')&.value.presence || llm_api_key
    end

    def embedding_local_provider?
      LOCAL_PROVIDERS.include?(embedding_provider) || !RubyLLM::Provider.providers.key?(embedding_provider.to_sym)
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

    # Returns embedding params with correct provider routing.
    # Uses the dedicated embedding provider when configured,
    # falling back to the chat provider when not.
    # This is essential because many LLM providers (Anthropic, etc.)
    # don't offer embedding APIs.
    def embedding_params_for(model_name)
      active = embedding_provider
      model_config = Llm::Models.models[model_name.to_s]
      model_provider = model_config&.dig('provider')

      if model_provider == active || (embedding_local_provider? && model_config.nil?)
        ruby_llm_provider = resolve_ruby_llm_provider(active)
        { model: model_name, provider: ruby_llm_provider, assume_model_exists: true }
      elsif model_provider == 'self_hosted'
        ruby_llm_provider = resolve_ruby_llm_provider(active)
        { model: model_name, provider: ruby_llm_provider, assume_model_exists: true }
      else
        { model: model_name }
      end
    end

    # Creates a per-request RubyLLM context configured for the embedding provider.
    # Used when the embedding provider differs from the chat provider
    # and requires separate API credentials.
    def with_embedding_context
      initialize!
      emb_provider = embedding_provider
      emb_base = embedding_api_base
      emb_key = embedding_api_key

      context = RubyLLM.context do |config|
        # Configure OpenAI credentials for backward compat and fallback
        config.openai_api_key = system_api_key if system_api_key.present?
        config.openai_api_base = openai_endpoint.chomp('/') if openai_endpoint.present?

        sym = emb_provider.to_sym
        if RubyLLM::Provider.providers.key?(sym)
          api_key_method = :"#{sym}_api_key"
          api_base_method = :"#{sym}_api_base"
          config.send(api_key_method, emb_key) if emb_key.present? && config.respond_to?(api_key_method)
          config.send(api_base_method, emb_base.chomp('/')) if emb_base.present? && config.respond_to?(api_base_method)
        elsif emb_base.present?
          # Custom OpenAI-compatible embedding provider
          config.openai_api_key = emb_key || 'dummy-key'
          config.openai_api_base = emb_base.chomp('/')
        end

        config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
        config.logger = Rails.logger
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

        # Configure the embedding provider if it differs from the chat provider
        configure_embedding_provider(config)

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

    # Configures the embedding provider's credentials when it differs from the chat provider.
    # This ensures RubyLLM has both providers' API keys available at the global level.
    # For custom OpenAI-compatible embedding endpoints, use `with_embedding_context` instead.
    def configure_embedding_provider(config)
      emb_provider = embedding_provider
      return if emb_provider == provider # Same as chat, already configured

      emb_base = embedding_api_base
      emb_key = embedding_api_key
      sym = emb_provider.to_sym

      if RubyLLM::Provider.providers.key?(sym)
        api_key_method = :"#{sym}_api_key"
        api_base_method = :"#{sym}_api_base"
        config.send(api_key_method, emb_key) if emb_key.present? && config.respond_to?(api_key_method)
        config.send(api_base_method, emb_base.chomp('/')) if emb_base.present? && config.respond_to?(api_base_method)
      end
      # Custom OpenAI-compatible embedding providers are handled via with_embedding_context
    end

    def system_api_key
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    end

    def openai_endpoint
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    end
  end
end