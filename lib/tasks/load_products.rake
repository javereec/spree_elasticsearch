namespace :spree_elasticsearch do
  desc "Load all products into the index."
  task :load_products => :environment do
    if Elasticsearch::Model.client.indices.exists index: Spree::ElasticsearchSettings.index
      Spree::Product.__elasticsearch__.import
      puts "Products successfully loaded into Elasticsearch indices."
    else
      puts "No existing elasticsearch client indices found. Run 'rake spree_elasticsearch:setup_indices' and try again."
    end
  end
end
