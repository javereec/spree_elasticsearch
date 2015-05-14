namespace :spree_elasticsearch do
  desc "Create Elasticsearch index."
  task :create_index => :environment do
    unless Elasticsearch::Model.client.indices.exists index: Spree::ElasticsearchSettings.index

      index_config = ::Rails.root.join('config/index.yml')
      Elasticsearch::Model.client.indices.create \
        index: Spree::ElasticsearchSettings.index,
        body: {
          settings: YAML.load(ERB.new(index_config.read).result)['settings'],
          mappings: Spree::Product.mappings.to_hash
        }
    end
  end
end
