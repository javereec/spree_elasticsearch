namespace :spree_elasticsearch do
  desc "Create Elasticsearch index."
  task :create_index => :environment do
    unless Elasticsearch::Model.client.indices.exists index: Spree::ElasticsearchSettings.index
      Elasticsearch::Model.client.indices.create \
        index: Spree::ElasticsearchSettings.index,
        body: {
          settings: {
            analysis: {
              analyzer: {
                 nGram_analyzer: {
                    type: "custom",
                    filter: ["lowercase", "asciifolding", "synonym", "ngram"],
                    tokenizer: "whitespace" },
                 whitespace_analyzer: {
                    type: "custom",
                    filter: ["lowercase", "asciifolding"],
                    tokenizer: "whitespace" }},
              filter: {
                synonym: {
                    type: "synonym",
                    synonyms_path: "analysis/synonyms.txt" },
                 ngram: {
                    max_gram: "20",
                    min_gram: "3",
                    type: "nGram",
                    token_chars: ["letter", "digit", "punctuation", "symbol"] }}}},
          mappings: Spree::Product.mappings.to_hash }
    end
  end
end
