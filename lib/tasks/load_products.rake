namespace :spree_elasticsearch do
  desc "Load all products into the index. It does this by iterating over all products and saving them."
  task :load_products => :environment do
    Spree::Product.all.each do |product|
      product.save
    end
  end
end