namespace :spree_elasticsearch do
  desc "Load all products into the index."
  task :load_products => :environment do
    unless Elasticsearch::Model.client.indices.exists index: Spree::ElasticsearchSettings.index
      Elasticsearch::Model.client.indices.create \
        index: Spree::ElasticsearchSettings.index,
        body: {
          settings: {
            number_of_shards: 1,
            number_of_replicas: 0,
            analysis: {
              analyzer: {
                 nGram_analyzer: {
                    type: "custom",
                    filter: ["lowercase", "asciifolding", "nGram_filter"],
                    tokenizer: "whitespace" },
                 whitespace_analyzer: {
                    type: "custom",
                    filter: ["lowercase", "asciifolding"],
                    tokenizer: "whitespace" }},
              filter: {
                 nGram_filter: {
                    max_gram: "20",
                    min_gram: "3",
                    type: "nGram",
                    token_chars: ["letter", "digit", "punctuation", "symbol"] }}}},
          mappings: Spree::Product.mappings.to_hash }
    end
    Spree::Product.__elasticsearch__.import
  end
end