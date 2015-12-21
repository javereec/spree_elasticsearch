module Spree
  module Search
    # The following search options are available.
    #   * taxon
    #   * keywords in name or description
    #   * properties values
    class Elasticsearch <  Spree::Core::Search::Base
      include ::Virtus.model

      attribute :query, String
      attribute :price_min, Float
      attribute :price_max, Float
      attribute :taxon, String
      attribute :taxons, Hash
      attribute :option_types, Hash
      attribute :browse_mode, Boolean, default: true
      attribute :properties, Hash
      attribute :per_page, String
      attribute :page, String
      attribute :sorting, String

      def initialize(params)
        self.current_currency = Spree::Config[:currency]
        prepare(params)
      end

      def retrieve_products
        from = (@page - 1) * Spree::Config.products_per_page
        search_result = Spree::Product.__elasticsearch__.search(
          Spree::Product::ElasticsearchQuery.new(
            query: query,
            taxon: taxon,
            taxons: taxons,
            option_types: option_types,
            browse_mode: browse_mode,
            from: from,
            price_min: price_min,
            price_max: price_max,
            properties: properties,
            sorting: sorting
          ).to_hash
        )
        search_result.records.limit(per_page).page(page)
      end

      protected

      # converts params to instance variables
      def prepare(params)
        @query = params[:keywords]
        @sorting = params[:sorting]
        @taxon = params[:taxon] unless params[:taxon].nil?
        @taxons = params[:taxons] unless params[:taxons].nil?
        @option_types = params[:option_types] unless params[:option_types].nil?
        @browse_mode = params[:browse_mode] unless params[:browse_mode].nil?
        if params[:search] && params[:search][:price]
          # price
          @price_min = params[:search][:price][:min].to_f
          @price_max = params[:search][:price][:max].to_f
          # properties
          @properties = params[:search][:properties]
        end

        @per_page = (params[:per_page].to_i <= 0) ? Spree::Config[:products_per_page] : params[:per_page].to_i
        @page = (params[:page].to_i <= 0) ? 1 : params[:page].to_i
      end
    end
  end
end
