require 'spec_helper'
require 'byebug'

module Spree
  describe Product do
    let(:a_product) { create(:product) }
    let(:another_product) { create(:product) }

    before do
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
                  type: 'custom',
                  filter: %w(lowercase asciifolding nGram_filter),
                  tokenizer: 'whitespace' },
                whitespace_analyzer: {
                  type: 'custom',
                  filter: %w(lowercase asciifolding),
                  tokenizer: 'whitespace' }},
              filter: {
                nGram_filter: {
                  max_gram: '20',
                  min_gram: '3',
                  type: 'nGram',
                  token_chars: %w(letter digit punctuation symbol)
                }
              }
            }
          },
          mappings: Spree::Product.mappings.to_hash
        }
    end

    context '#index' do
      before { a_product.name = 'updated name' }

      it 'updates an existing product in the index' do
        expect(a_product.__elasticsearch__.index_document['_version']).to eq 2
        expect(Product.get(a_product.id).name).to eq 'updated name'
      end
    end

    context 'get' do
      subject { Product.get(a_product.id).name }

      it { is_expected.to eq a_product.name }
    end

    describe 'search' do
      context 'retrieves a product based on name' do
        before do
          another_product.name = 'Foobar'
          another_product.__elasticsearch__.index_document
          Product.__elasticsearch__.refresh_index!
        end

        let(:products) do
          Product.__elasticsearch__.search(Spree::Product::ElasticsearchQuery.new(query: another_product.name))
        end

        it { expect(products.results.total).to eq 1 }
        it { expect(products.results.any?{ |product| product.name == another_product.name }).to be_truthy }
      end

      context 'retrieves products based on part of the name' do
        before do
          a_product.name = 'Product 1'
          another_product.name = 'Product 2'
          a_product.__elasticsearch__.index_document
          another_product.__elasticsearch__.index_document
          Product.__elasticsearch__.refresh_index!
        end

        let(:products) { Product.__elasticsearch__.search(Spree::Product::ElasticsearchQuery.new(query: 'Product')) }

        it { expect(products.results.total).to eq 2 }
        it { expect(products.results.any?{ |product| product.name == a_product.name }).to be_truthy }
        it { expect(products.results.any?{ |product| product.name == another_product.name }).to be_truthy }
      end

      context 'retrieves products default sorted on name' do
        before do
          a_product.name = 'Product 1'
          a_product.__elasticsearch__.index_document
          another_product.name = 'Product 2'
          another_product.__elasticsearch__.index_document
          Product.__elasticsearch__.refresh_index!
        end

        let(:products) { Product.__elasticsearch__.search(Spree::Product::ElasticsearchQuery.new) }

        it { expect(products.results.total).to eq 2 }
        it { expect(products.results.to_a[0].name).to eq a_product.name }
        it { expect(products.results.to_a[1].name).to eq another_product.name }
      end

      context 'filters products based on price' do
        before do
          a_product.price = 1
          a_product.__elasticsearch__.index_document
          another_product.price = 3
          another_product.__elasticsearch__.index_document
          Product.__elasticsearch__.refresh_index!
        end

        let(:products) do
          Product.__elasticsearch__.search(Spree::Product::ElasticsearchQuery.new(price_min: 2, price_max: 4))
        end

        it { expect(products.results.total).to eq 1 }
        it { expect(products.results.to_a[0].name).to eq another_product.name }
      end

      context 'ignores price filter when price_min is greater than price_max' do
        before do
          a_product.price = 1
          a_product.__elasticsearch__.index_document
          another_product.price = 3
          another_product.__elasticsearch__.index_document
          Product.__elasticsearch__.refresh_index!
        end

        let(:products) do
          Product.__elasticsearch__.search(Spree::Product::ElasticsearchQuery.new(price_min: 4, price_max: 2))
        end

        it { expect(products.results.total).to eq 2 }
      end

      context 'ignores price filter when price_min and/or price_max is nil' do
        before do
          a_product.price = 1
          a_product.__elasticsearch__.index_document
          another_product.price = 3
          another_product.__elasticsearch__.index_document
          Product.__elasticsearch__.refresh_index!
        end

        let(:products_min_price) do
          Product.__elasticsearch__.search(Spree::Product::ElasticsearchQuery.new(price_min: 2))
        end
        let(:products_max_price) do
          Product.__elasticsearch__.search(Spree::Product::ElasticsearchQuery.new(price_max: 2))
        end
        let(:products) do
          Product.__elasticsearch__.search(Spree::Product::ElasticsearchQuery.new(price_min: nil, price_max: nil))
        end

        it { expect(products_min_price.results.total).to eq 2 }
        it { expect(products_max_price.results.total).to eq 2 }
        it { expect(products.results.total).to eq 2 }
      end

      describe 'properties' do
        let(:product) { Product.find(a_product.id) }

        subject { products.results }

        context 'allows searching on property' do
          before do
            a_product.set_property('the_prop', 'a_value')
            product.save
            Product.__elasticsearch__.refresh_index!
          end


          let(:products) do
            Product.__elasticsearch__.search(
              Spree::Product::ElasticsearchQuery.new(properties: { the_prop: %w(a_value b_value) })
            )
          end

          it { expect(subject.count).to eq 1 }
          it { expect(subject.to_a[0].name).to eq product.name }
        end

        context 'allows searching on different property values (OR relation)' do
          before do
            a_product.set_property('the_prop', 'a_value')
            another_product.set_property('the_prop', 'b_value')
            product_one.save
            product_two.save
            Product.__elasticsearch__.refresh_index!
          end

          let(:product_one) { Product.find(a_product.id) }
          let(:product_two) { Product.find(another_product.id) }

          let(:products) do
            Product.__elasticsearch__.search(
              Spree::Product::ElasticsearchQuery.new(properties: { the_prop: %w(a_value b_value) })
            )
          end

          it { expect(subject.count).to eq 2 }
          it { expect(subject.to_a.find { |product| product.name == product_one.name }).to_not be_nil }
          it { expect(subject.to_a.find { |product| product.name == product_two.name }).to_not be_nil }
        end

        context 'allows searching on different properties (AND relation)' do
          before do
            a_product.set_property('the_prop', 'a_value')
            a_product.set_property('another_prop', 'a_value')
            product.save
            another_product.set_property('the_prop', 'a_value')
            another_product.set_property('another_prop', 'b_value')
            Product.find(another_product.id).save
            Product.__elasticsearch__.refresh_index!
          end

          let(:products) do
            Product.__elasticsearch__.search(
              Spree::Product::ElasticsearchQuery.new(properties: { the_prop: ['a_value'], another_prop: ['a_value'] })
            )
          end

          it { expect(subject.count).to eq 1 }
          it { expect(subject.to_a[0].name).to eq product.name }
        end
      end
    end

    context 'document_type returns the name of the class' do
      subject { Product.document_type }

      it { is_expected.to eq 'spree_product' }
    end
  end
end
