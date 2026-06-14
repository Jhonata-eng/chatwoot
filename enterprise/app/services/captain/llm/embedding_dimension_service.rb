# frozen_string_literal: true

# Handles migrating embedding vector column dimensions when the embedding model changes.
# Since different embedding models produce vectors of different sizes
# (e.g., OpenAI text-embedding-3-small = 1536, Ollama nomic-embed-text = 768),
# the database vector columns must be resized and all embeddings regenerated.
class Captain::Llm::EmbeddingDimensionService
  EMBEDDING_TABLES = {
    'captain_assistant_responses' => 'Captain::AssistantResponse',
    'article_embeddings' => 'ArticleEmbedding'
  }.freeze

  # Migrate the vector column dimensions from the current to a new size.
  # Uses a safe swap approach: add new column → drop old → rename.
  # All existing embeddings are cleared and must be regenerated.
  def migrate_dimensions(new_dimensions)
    current = Llm::Config.embedding_dimensions
    return if current == new_dimensions

    Rails.logger.info "[Captain] Migrating embedding dimensions from #{current} to #{new_dimensions}"

    EMBEDDING_TABLES.each_key do |table_name|
      migrate_table(table_name, from: current, to: new_dimensions)
    end

    # Update the config
    config = InstallationConfig.find_or_create_by(name: 'CAPTAIN_EMBEDDING_DIMENSIONS')
    config.value = new_dimensions
    config.save!

    # Enqueue re-embedding for all records
    enqueue_re_embedding_jobs

    Rails.logger.info "[Captain] Embedding dimension migration complete. Re-embedding jobs enqueued."
  end

  # Re-embed all records using the current embedding model.
  # Useful when the model changes but dimensions stay the same,
  # or after a dimension migration to regenerate vectors.
  def reembed_all
    model = Captain::Llm::EmbeddingService.embedding_model
    Rails.logger.info "[Captain] Re-embedding all records with model: #{model}"

    Captain::AssistantResponse.find_each do |response|
      Captain::Llm::UpdateEmbeddingJob.perform_later(response, "#{response.question}: #{response.answer}")
    end

    ArticleEmbedding.find_each do |embedding|
      Captain::Llm::UpdateEmbeddingJob.perform_later(embedding, embedding.term)
    end

    Rails.logger.info "[Captain] Re-embedding jobs enqueued."
  end

  # Get the expected dimensions for a given embedding model.
  # Returns nil if unknown (user must provide the value manually).
  def dimensions_for_model(model_name)
    model_config = Llm::Models.models[model_name.to_s]
    model_config&.dig('embedding_dimensions')
  end

  private

  def migrate_table(table_name, from:, to:)
    ActiveRecord::Base.connection.execute("DROP INDEX IF EXISTS index_#{table_name}_on_embedding")
    ActiveRecord::Base.connection.execute("DROP INDEX IF EXISTS vector_idx_#{table_name}_embedding")

    # Drop the old column and re-add with new dimensions
    ActiveRecord::Base.connection.remove_column(table_name, :embedding, :vector, limit: from)
    ActiveRecord::Base.connection.add_column(table_name, :embedding, :vector, limit: to)

    # Recreate the IVFFlat index
    # Only create index if there are enough rows for IVFFlat training
    create_vector_index(table_name)
  end

  def create_vector_index(table_name)
    # Use HNSW index which doesn't require training data and supports concurrent builds
    ActiveRecord::Base.connection.execute(<<~SQL)
      CREATE INDEX IF NOT EXISTS vector_idx_#{table_name}_embedding
      ON #{table_name}
      USING hnsw (embedding vector_l2_ops)
      WITH (m = 16, ef_construction = 64)
    SQL
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn "[Captain] Failed to create HNSW index on #{table_name}: #{e.message}. Skipping index creation."
  end

  def enqueue_re_embedding_jobs
    Captain::AssistantResponse.find_each do |response|
      Captain::Llm::UpdateEmbeddingJob.perform_later(response, "#{response.question}: #{response.answer}")
    end

    ArticleEmbedding.find_each do |embedding|
      Captain::Llm::UpdateEmbeddingJob.perform_later(embedding, embedding.term)
    end
  end
end