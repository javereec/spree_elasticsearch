module Spree
  module Search
    # The following search options are available.
    #   * taxon
    #   * keywords in name or description
    #   * properties values
    class Elasticsearch <  Spree::Core::Search::Base
      include ::Virtus.model

      attribute :query, String
      attribute :price_low, Float
      attribute :price_high, Float
      attribute :taxons, Array
      attribute :properties, Hash
      attribute :per_page, String
      attribute :page, String

      def initialize(params)
        self.current_currency = Spree::Config[:currency]
        prepare(params)
      end

      def retrieve_products
        from = (@page - 1) * Spree::Config.products_per_page
        price = [price_low, price_high] if (price_low && price_high)
        Spree::Product.search(
          query: query,
          taxons: taxons,
          from: from,
          price: price,
          properties: properties
        )
      end

      protected

      # converts params to instance variables
      def prepare(params)
        @query = params[:keywords]
        # taxon
        taxon = params[:taxon].blank? ? nil : Spree::Taxon.find(params[:taxon])
        @taxons = taxon ? taxon.self_and_descendants.map(&:name) : nil
        if params[:search]
          # price
          @price_low = params[:search][:price][:min]
          @price_high = params[:search][:price][:max]
          # properties
          @properties = params[:search][:properties]
        end

        @per_page = (params[:per_page].to_i <= 0) ? Spree::Config[:products_per_page] : params[:per_page].to_i
        @page = (params[:page].to_i <= 0) ? 1 : params[:page].to_i
      end
    end
  end
end