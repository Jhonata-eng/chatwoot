class Api::V1::Accounts::Captain::PreferencesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :authorize_account_update, only: [:update]

  def show
    render json: preferences_payload
  end

  def update
    params_to_update = captain_params

    # When the embedding model changes, check if dimension migration is needed
    if params_to_update[:captain_models]&.key?('help_center_search')
      handle_embedding_model_change(params_to_update[:captain_models]['help_center_search'])
    end

    @current_account.captain_models = params_to_update[:captain_models] if params_to_update[:captain_models]
    @current_account.captain_features = params_to_update[:captain_features] if params_to_update[:captain_features]
    @current_account.save!

    render json: preferences_payload
  end

  private

  def preferences_payload
    {
      providers: Llm::Models.providers,
      models: Llm::Models.models,
      features: features_with_account_preferences,
      embedding_config: {
        provider: Llm::Config.embedding_provider,
        separate_provider: Llm::Config.embedding_provider != Llm::Config.provider,
        local_provider: Llm::Config.embedding_local_provider?
      }
    }
  end

  def authorize_account_update
    authorize @current_account, :update?
  end

  def captain_params
    permitted = {}
    permitted[:captain_models] = merged_captain_models if params[:captain_models].present?
    permitted[:captain_features] = merged_captain_features if params[:captain_features].present?
    permitted
  end

  def merged_captain_models
    existing_models = @current_account.captain_models || {}
    existing_models.merge(permitted_captain_models)
  end

  def merged_captain_features
    existing_features = @current_account.captain_features || {}
    existing_features.merge(permitted_captain_features)
  end

  def permitted_captain_models
    params.require(:captain_models).permit(
      :editor, :assistant, :copilot, :label_suggestion,
      :audio_transcription, :help_center_search
    ).to_h.stringify_keys
  end

  def permitted_captain_features
    params.require(:captain_features).permit(
      :editor, :assistant, :copilot, :label_suggestion,
      :audio_transcription, :help_center_search
    ).to_h.stringify_keys
  end

  def features_with_account_preferences
    preferences = Current.account.captain_preferences
    account_features = preferences[:features] || {}
    account_models = preferences[:models] || {}

    Llm::Models.feature_keys.index_with do |feature_key|
      config = Llm::Models.feature_config(feature_key)
      config.merge(
        enabled: account_features[feature_key] == true,
        selected: account_models[feature_key] || config[:default]
      )
    end
  end

  # When the embedding model changes to one with different dimensions,
  # auto-migrate the vector columns and re-embed all records.
  # Only available in Enterprise edition (where EmbeddingDimensionService exists).
  def handle_embedding_model_change(model_name)
    return if model_name.blank?
    return unless defined?(Captain::Llm::EmbeddingDimensionService)

    model_dims = Captain::Llm::EmbeddingDimensionService.new.dimensions_for_model(model_name)
    return if model_dims.nil? # Unknown model — user's responsibility

    current_dims = Llm::Config.embedding_dimensions
    return if model_dims == current_dims # Same dimensions, no migration needed

    # Auto-migrate dimensions and re-embed all records
    Captain::Llm::EmbeddingDimensionService.new.migrate_dimensions(model_dims)
  end
end
