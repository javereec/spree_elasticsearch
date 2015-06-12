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
      attribute :discount_min, Integer
      attribute :discount_max, Integer
      attribute :taxons, Array
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
        search_result = Spree::Product.__elasticsearch__.search(
          Spree::Product::ElasticsearchQuery.new(
            query: query,
            taxons: taxons,
            browse_mode: browse_mode,
            price_min: price_min,
            price_max: price_max,
            discount_min: discount_min,
            discount_max: discount_max,
            properties: properties || {},
            sorting: sorting
          ).to_hash
        )
        @result = search_result.limit(per_page).page(page)
        @result.records
      end

      def facets
        @result.response.aggregations
      end

      module Escaping
        LUCENE_SPECIAL_CHARACTERS = Regexp.new("(" + %w[
          + - && || ! ( ) { } [ ] ^ " ~ * ? : \\ /
        ].map { |s| Regexp.escape(s) }.join("|") + ")")

        LUCENE_BOOLEANS = /\b(AND|OR|NOT)\b/

        def self.escape(s)
          # 6 slashes =>
          #  ruby reads it as 3 backslashes =>
          #    the first 2 =>
          #      go into the regex engine which reads it as a single literal backslash
          #    the last one combined with the "1" to insert the first match group
          special_chars_escaped = s.gsub(LUCENE_SPECIAL_CHARACTERS, '\\\\\1')

          # Map something like 'fish AND chips' to 'fish "AND" chips', to avoid
          # Lucene trying to parse it as a query conjunction
          special_chars_escaped.gsub(LUCENE_BOOLEANS, '"\1"')
        end
      end

      protected

      # converts params to instance variables
      def prepare(params)
        @query = Escaping.escape(params[:keywords] || "")
        @sorting = params[:sorting]
        @taxons = params[:taxon] unless params[:taxon].nil?
        @browse_mode = params[:browse_mode] unless params[:browse_mode].nil?
        if params[:search]
          # price
          if params[:search][:price]
            @price_min = params[:search][:price][:min].to_f
            @price_max = params[:search][:price][:max].to_f
          end
          # discount_rate
          if params[:search][:discount]
            @discount_min = params[:search][:discount][:min].to_f
            @discount_max = params[:search][:discount][:max].to_f
          end
          # properties
          @properties = params[:search][:properties]
        end

        @per_page = (params[:per_page].to_i <= 0) ? Spree::Config[:products_per_page] : params[:per_page].to_i
        @page = (params[:page].to_i <= 0) ? 1 : params[:page].to_i
      end
    end
  end
end
