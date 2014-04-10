require 'spec_helper'
require 'byebug'

module Spree
  describe Spree::Product do
    let(:a_product) { create(:product) }
    let(:another_product) { create(:product) }

    before(:each) do
      # for clean testing, delete index, create new one and create/update mapping
      Spree::Product.delete_all
      client = Elasticsearch::Client.new log: true, hosts: Spree::ElasticsearchSettings.hosts
      client.indices.create index: Spree::ElasticsearchSettings.index, body: {}
      client.indices.put_mapping index: Spree::ElasticsearchSettings.index, type: Spree::Product.type, body: Spree::Product.mapping
    end

    context "#index" do
      it "updates an existing product in the index" do
        a_product.name = "updated name"
        result = a_product.index
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
        another_product.index
        sleep 3 # allow some time for elasticsearch
        products = Spree::Product.search(query: another_product.name)
        products.total.should == 1
        products.any?{ |p| p.name == another_product.name }.should be_true
      end

      it "retrieves products based on part of the name" do
        a_product.name = "Product 1"
        another_product.name = "Product 2"
        a_product.index
        another_product.index
        sleep 3 # allow some time for elasticsearch
        products = Spree::Product.search(query: 'Product')
        products.total.should == 2
        products.any?{ |p| p.name == a_product.name }.should be_true
        products.any?{ |p| p.name == another_product.name }.should be_true
      end

      it "retrieves products default sorted on name" do
        a_product.name = "Product 1"
        a_product.index
        another_product.name = "Product 2"
        another_product.index
        sleep 3 # allow some time for elasticsearch
        products = Spree::Product.search
        products.total.should == 2
        products.to_a[0].name.should == a_product.name
        products.to_a[1].name.should == another_product.name
      end

      context 'properties' do
        it "allows searching on property" do
          a_product.set_property('the_prop', 'a_value')
          product = Spree::Product.find(a_product.id)
          product.save
          sleep 3 # allow some time for elasticsearch
          products = Spree::Product.search(properties: { 'the_prop' => ['a_value'] })
          products.count.should == 1
          products.to_a[0].name.should == product.name
        end

        it "allows searching on different property values (OR relation)" do
          a_product.set_property('the_prop', 'a_value')
          product_one = Spree::Product.find(a_product.id)
          product_one.save
          another_product.set_property('the_prop', 'b_value')
          product_two = Spree::Product.find(another_product.id)
          product_two.save
          sleep 3 # allow some time for elasticsearch
          products = Spree::Product.search(properties: { 'the_prop' => ['a_value', 'b_value'] })
          products.count.should == 2
          products.to_a.find {|p| p.name == product_one.name}.should_not be_nil
          products.to_a.find {|p| p.name == product_two.name}.should_not be_nil
        end 

        it "allows searching on different properties (AND relation)" do
          a_product.set_property('the_prop', 'a_value')
          a_product.set_property('another_prop', 'a_value')
          product = Spree::Product.find(a_product.id)
          product.save
          another_product.set_property('the_prop', 'a_value')
          another_product.set_property('another_prop', 'b_value')
          Spree::Product.find(another_product.id).save
          sleep 3 # allow some time for elasticsearch
          products = Spree::Product.search(properties: { 'the_prop' => ['a_value'], 'another_prop' => ['a_value'] })
          products.count.should == 1
          products.to_a[0].name.should == product.name
        end        
      end

      context 'facets' do
        it "contains price facet" do
          products = Spree::Product.search(name: a_product.name)
          facet = products.facets.find {|facet| facet.name == "price"}
          facet.should_not be_nil
          facet.type.should == "statistical"
        end
      end
    end

    context "update_index" do
      it "indexes when saved and available" do
        a_product = build(:product)
        a_product.save
        sleep 1
        product_from_index = Product.get(a_product.id)
        product_from_index.name.should == a_product.name
      end

      it "removes from index when saved and not available" do
        a_product.available_on = Time.now + 1.day
        a_product.save
        sleep 1
        product_from_index = Product.get(a_product.id)
        product_from_index.name.should == a_product.name
      end

      it "removes from index when saved and deleted" do
        a_product.destroy
        sleep 1
        expect { Product.get(a_product.id) }.to raise_error(Elasticsearch::Transport::Transport::Errors::NotFound)
      end
    end

    context 'type' do
      it 'returns the name of the class' do
        Product.type.should == 'spree_product'
      end
    end

    context 'third party support' do
      it 'returns maximum updated_at for caching purposes' do
        a_product.index
        sleep 2
        products = Spree::Product.search(query: "name:\"#{a_product.name}\"")
        products.maximum(:updated_at).to_i.should == a_product.updated_at.to_i # == doesn't seem to work for ActiveSupport::TimeWithZone, converting to integer
      end

      it 'returns 0 as maximum updated_at when no results' do
        products = Spree::Product.search(query: 'qwertyasdfg')
        products.maximum(:updated_at).should == 0
      end
    end
  end
end