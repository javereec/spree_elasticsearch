namespace :spree_elasticsearch do
  desc "Delete any existing indices and create all from scratch."
  task :setup_indices => :environment do
    Elasticsearch::Model.client.indices.delete index: '_all'
    Elasticsearch::Model.client.indices.create \
      index: Spree::ElasticsearchSettings.index,
      body: {
        settings: Spree::Product.settings.to_hash,
        mappings: Spree::Product.mappings.to_hash }
    puts "Elasticsearch indices created successfully. Please run 'rake spree_elasticsearch:load_products' to load your products into the index."
  end
end
