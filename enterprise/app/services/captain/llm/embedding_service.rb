class Captain::Llm::EmbeddingService
  include Integrations::LlmInstrumentation

  class EmbeddingsError < StandardError; end

  def initialize(account_id: nil)
    Llm::Config.initialize!
    @account_id = account_id
    @account = Account.find_by(id: account_id) if account_id
  end

  # Returns the embedding model for the given account.
  # Per-account model preference takes precedence over the global default.
  def self.embedding_model(account: nil)
    # Per-account model preference takes precedence
    account_model = account&.captain_help_center_search_model
    return account_model if account_model.present? && valid_embedding_model?(account_model)

    # Fall back to global InstallationConfig
    InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence || LlmConstants::DEFAULT_EMBEDDING_MODEL
  end

  def self.valid_embedding_model?(model_name)
    Llm::Models.valid_model_for?('help_center_search', model_name) || Llm::Models.self_hosted_model?(model_name)
  end

  def get_embedding(content, model: nil)
    return [] if content.blank?

    model ||= self.class.embedding_model(account: @account)
    embedding_params = Llm::Config.embedding_params_for(model)

    instrument_embedding_call(instrumentation_params(content, model)) do
      # Use a dedicated embedding context when the embedding provider
      # differs from the chat provider and has its own API base.
      # This ensures embeddings route through the correct provider.
      if separate_embedding_provider?
        Llm::Config.with_embedding_context do |context|
          context.embed(content, **embedding_params).vectors
        end
      else
        RubyLLM.embed(content, **embedding_params).vectors
      end
    end
  rescue RubyLLM::Error => e
    Rails.logger.error "Embedding API Error: #{e.message}"
    raise EmbeddingsError, "Failed to create an embedding: #{e.message}"
  end

  private

  # Returns true when the embedding provider is configured separately from the
  # chat provider and has its own API base URL.
  def separate_embedding_provider?
    Llm::Config.embedding_provider != Llm::Config.provider && Llm::Config.embedding_api_base.present?
  end

  def instrumentation_params(content, model)
    {
      span_name: 'llm.captain.embedding',
      model: model,
      input: content,
      feature_name: 'embedding',
      account_id: @account_id
    }
  end
end