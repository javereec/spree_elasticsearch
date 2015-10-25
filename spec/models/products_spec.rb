require 'spec_helper'
require 'byebug'

module Spree
  describe Product do
    let(:a_product) { create(:product) }
    let(:another_product) { create(:product) }

    before(:each) do
      # for clean testing, delete index, create new one and create/update mapping
      Product.delete_all
      client = Elasticsearch::Client.new log: true, hosts: ElasticsearchSettings.hosts
      if Elasticsearch::Model.client.indices.exists index: Spree::ElasticsearchSettings.index
        client.indices.delete index: ElasticsearchSettings.index
      end
      client.indices.create \
        index: ElasticsearchSettings.index,
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
                  token_chars: ["letter", "digit", "punctuation", "symbol"]
                }
              }
            }
          },
          mappings: Spree::Product.mappings.to_hash
        }
    end

    context "#index" do
      it "updates an existing product in the index" do
        a_product.name = "updated name"
        result = a_product.__elasticsearch__.index_document
        result['_version'].should == 2
        product_from_index = Product.get(a_product.id)
        product_from_index.name.should == 'updated name'
      end
    end

    context 'get' do
      it "retrieves a product form the index" do
        product_from_index = Product.get(a_product.id)
        product_from_index.name.should == a_product.name
      end
    end

    context 'search' do
      it "retrieves a product based on name" do
        another_product.name = "Foobar"
        another_product.__elasticsearch__.index_document
        sleep 3 # allow some time for elasticsearch
        products = Product.__elasticsearch__.search(
          Spree::Product::ElasticsearchQuery.new(query: another_product.name)
        )
        # products = Product.__elasticsearch__.search(query: another_product.name)
        products.results.total.should == 1
        products.results.any?{ |p| p.name == another_product.name }.should be_true
      end

      it "retrieves products based on part of the name" do
        a_product.name = "Product 1"
        another_product.name = "Product 2"
        a_product.__elasticsearch__.index_document
        another_product.__elasticsearch__.index_document
        sleep 3 # allow some time for elasticsearch
        products = Product.__elasticsearch__.search(
          Spree::Product::ElasticsearchQuery.new(query: 'Product')
        )
        products.results.total.should == 2
        products.results.any?{ |p| p.name == a_product.name }.should be_true
        products.results.any?{ |p| p.name == another_product.name }.should be_true
      end

      it "retrieves products default sorted on name" do
        a_product.name = "Product 1"
        a_product.__elasticsearch__.index_document
        another_product.name = "Product 2"
        another_product.__elasticsearch__.index_document
        sleep 3 # allow some time for elasticsearch
        products = Product.__elasticsearch__.search(
          Spree::Product::ElasticsearchQuery.new
        )
        products.results.total.should == 2
        products.results.to_a[0].name.should == a_product.name
        products.results.to_a[1].name.should == another_product.name
      end

      it "filters products based on price" do
        a_product.price = 1
        a_product.__elasticsearch__.index_document
        another_product.price = 3
        another_product.__elasticsearch__.index_document
        sleep 3 # allow some time for elasticsearch
        products = Product.__elasticsearch__.search(
          Spree::Product::ElasticsearchQuery.new(price_min: 2, price_max: 4)
        )
        products.results.total.should == 1
        products.results.to_a[0].name.should == another_product.name
      end

      it "ignores price filter when price_min is greater than price_max" do
        a_product.price = 1
        a_product.__elasticsearch__.index_document
        another_product.price = 3
        another_product.__elasticsearch__.index_document
        sleep 3 # allow some time for elasticsearch
        products = Product.__elasticsearch__.search(
          Spree::Product::ElasticsearchQuery.new(price_min: 4, price_max: 2)
        )
        products.results.total.should == 2
      end

      it "ignores price filter when price_min and/or price_max is nil" do
        a_product.price = 1
        a_product.__elasticsearch__.index_document
        another_product.price = 3
        another_product.__elasticsearch__.index_document
        sleep 3 # allow some time for elasticsearch
        products = Product.__elasticsearch__.search(
          Spree::Product::ElasticsearchQuery.new(price_min: 2)
        )
        products.results.total.should == 2
        products = Product.__elasticsearch__.search(
          Spree::Product::ElasticsearchQuery.new(price_max: 2)
        )
        products.results.total.should == 2
        products = Product.__elasticsearch__.search(
          Spree::Product::ElasticsearchQuery.new(price_min: nil, price_max: nil)
        )
        products.results.total.should == 2
      end

      context 'properties' do
        it "allows searching on property" do
          a_product.set_property('the_prop', 'a_value')
          product = Product.find(a_product.id)
          product.save
          sleep 3 # allow some time for elasticsearch
          products = Product.__elasticsearch__.search(
            Spree::Product::ElasticsearchQuery.new(properties: { 'the_prop' => ['a_value', 'b_value'] })
          )
          products.results.count.should == 1
          products.results.to_a[0].name.should == product.name
        end

        it "allows searching on different property values (OR relation)" do
          a_product.set_property('the_prop', 'a_value')
          product_one = Product.find(a_product.id)
          product_one.save
          another_product.set_property('the_prop', 'b_value')
          product_two = Product.find(another_product.id)
          product_two.save
          sleep 3 # allow some time for elasticsearch
          products = Product.__elasticsearch__.search(
            Spree::Product::ElasticsearchQuery.new(properties: { 'the_prop' => ['a_value', 'b_value'] })
          )
          products.results.count.should == 2
          products.results.to_a.find {|p| p.name == product_one.name}.should_not be_nil
          products.results.to_a.find {|p| p.name == product_two.name}.should_not be_nil
        end

        it "allows searching on different properties (AND relation)" do
          a_product.set_property('the_prop', 'a_value')
          a_product.set_property('another_prop', 'a_value')
          product = Product.find(a_product.id)
          product.save
          another_product.set_property('the_prop', 'a_value')
          another_product.set_property('another_prop', 'b_value')
          Product.find(another_product.id).save
          sleep 3 # allow some time for elasticsearch
          products = Product.__elasticsearch__.search(
            Spree::Product::ElasticsearchQuery.new(properties: { 'the_prop' => ['a_value'], 'another_prop' => ['a_value'] })
          )
          products.results.count.should == 1
          products.results.to_a[0].name.should == product.name
        end
      end
    end

    context 'document_type' do
      it 'returns the name of the class' do
        Product.document_type.should == 'spree_product'
      end
    end
  end
end
