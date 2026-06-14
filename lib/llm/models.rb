module Llm::Models
  CONFIG = YAML.load_file(Rails.root.join('config/llm.yml')).freeze

  class << self
    def providers = CONFIG['providers']
    def models = CONFIG['models']
    def features = CONFIG['features']
    def feature_keys = CONFIG['features'].keys

    def default_model_for(feature)
      CONFIG.dig('features', feature.to_s, 'default')
    end

    def models_for(feature)
      CONFIG.dig('features', feature.to_s, 'models') || []
    end

    def valid_model_for?(feature, model_name)
      models_for(feature).include?(model_name.to_s)
    end

    def feature_config(feature_key)
      feature = features[feature_key.to_s]
      return nil unless feature

      {
        models: feature['models'].map do |model_name|
          model = models[model_name]
          {
            id: model_name,
            display_name: model['display_name'],
            provider: model['provider'],
            coming_soon: model['coming_soon'],
            credit_multiplier: model['credit_multiplier'],
            supports_tools: model['supports_tools'],
            embedding_dimensions: model['embedding_dimensions']
          }.compact
        end,
        default: feature['default']
      }
    end

    # Check if a model is a self-hosted model (either in the registry or when a
    # self-hosted provider is active). Self-hosted models are dynamic — users can
    # pull whatever they want — so strict validation is skipped.
    def self_hosted_model?(model_name)
      models.dig(model_name.to_s, 'provider') == 'self_hosted' || self_hosted_provider_active?
    end

    def self_hosted_provider_active?
      Llm::Config.local_provider?
    end
  end
end