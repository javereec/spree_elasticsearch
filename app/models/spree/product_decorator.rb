module Spree
  Product.class_eval do
    include Elasticsearch::Model

    index_name Spree::ElasticsearchSettings.index
    document_type 'spree_product'

    mapping _all: { analyzer: 'nGram_analyzer', search_analyzer: 'whitespace_analyzer' } do
      indexes :name, type: 'multi_field' do
        indexes :name, type: 'string', analyzer: 'nGram_analyzer', boost: 100
        indexes :untouched, type: 'string', include_in_all: false, index: 'not_analyzed'
      end

      indexes :description, analyzer: 'snowball'
      indexes :available_on, type: 'date', format: 'dateOptionalTime', include_in_all: false
      indexes :price, type: 'double'
      indexes :sku, type: 'string', index: 'not_analyzed'
      indexes :taxon_ids, type: 'string', index: 'not_analyzed'
      indexes :properties, type: 'string', index: 'not_analyzed'
    end

    def as_indexed_json(options={})
      result = as_json({
        methods: [:price, :sku],
        only: [:available_on, :description, :name],
        include: {
          variants: {
            only: [:sku],
            include: {
              option_values: {
                only: [:name, :presentation]
              }
            }
          }
        }
      })
      result[:properties] = property_list unless property_list.empty?
      result[:taxon_ids] = taxons.map(&:self_and_ancestors).flatten.uniq.map(&:id) unless taxons.empty?
      result
    end

    def self.get(product_id)
      Elasticsearch::Model::Response::Result.new(__elasticsearch__.client.get index: index_name, type: document_type, id: product_id)
    end

    # Inner class used to query elasticsearch. The idea is that the query is dynamically build based on the parameters.
    class Product::ElasticsearchQuery
      include ::Virtus.model

      attribute :from, Integer, default: 0
      attribute :price_min, Float
      attribute :price_max, Float
      attribute :properties, Hash
      attribute :query, String
      attribute :taxons, Array
      attribute :browse_mode, Boolean
      attribute :sorting, String

      # When browse_mode is enabled, the taxon filter is placed at top level. This causes the results to be limited, but facetting is done on the complete dataset.
      # When browse_mode is disabled, the taxon filter is placed inside the filtered query. This causes the facets to be limited to the resulting set.

      # Method that creates the actual query based on the current attributes.
      # The idea is to always to use the following schema and fill in the blanks.
      # {
      #   query: {
      #     filtered: {
      #       query: {
      #         query_string: { query: , fields: [] }
      #       }
      #       filter: {
      #         and: [
      #           { terms: { taxons: [] } },
      #           { terms: { properties: [] } }
      #         ]
      #       }
      #     }
      #   }
      #   filter: { range: { price: { lte: , gte: } } },
      #   sort: [],
      #   from: ,
      #   aggregations:
      # }
      def to_hash
        q = { match_all: {} }
        unless query.blank? # nil or empty
          q = { query_string: { query: query, fields: ['name^5','description','sku'], default_operator: 'AND', use_dis_max: true } }
        end
        query = q

        and_filter = []
        unless @properties.nil? || @properties.empty?
          # transform properties from [{"key1" => ["value_a","value_b"]},{"key2" => ["value_a"]}
          # to { terms: { properties: ["key1||value_a","key1||value_b"] }
          #    { terms: { properties: ["key2||value_a"] }
          # This enforces "and" relation between different property values and "or" relation between same property values
          properties = @properties.map{ |key, value| [key].product(value) }.map do |pair|
            and_filter << { terms: { properties: pair.map { |property| property.join('||') } } }
          end
        end

        sorting = case @sorting
        when 'name_asc'
          [ { 'name.untouched' => { order: 'asc' } }, { price: { order: 'asc' } }, '_score' ]
        when 'name_desc'
          [ { 'name.untouched' => { order: 'desc' } }, { price: { order: 'asc' } }, '_score' ]
        when 'price_asc'
          [ { 'price' => { order: 'asc' } }, { 'name.untouched' => { order: 'asc' } }, '_score' ]
        when 'price_desc'
          [ { 'price' => { order: 'desc' } }, { 'name.untouched' => { order: 'asc' } }, '_score' ]
        when 'score'
          [ '_score', { 'name.untouched' => { order: 'asc' } }, { price: { order: 'asc' } } ]
        else
          [ { 'name.untouched' => { order: 'asc' } }, { price: { order: 'asc' } }, '_score' ]
        end

        # aggregations
        aggregations = {
          price: { stats: { field: 'price' } },
          properties: { terms: { field: 'properties', order: { _count: 'asc' }, size: 1000000 } },
          taxon_ids: { terms: { field: 'taxon_ids', size: 1000000 } }
        }

        # basic skeleton
        result = {
          min_score: 0.1,
          query: { filtered: {} },
          sort: sorting,
          from: from,
          aggregations: aggregations
        }

        # add query and filters to filtered
        result[:query][:filtered][:query] = query
        # taxon and property filters have an effect on the facets
        and_filter << { terms: { taxon_ids: taxons } } unless taxons.empty?
        # only return products that are available
        and_filter << { range: { available_on: { lte: 'now' } } }
        result[:query][:filtered][:filter] = { and: and_filter } unless and_filter.empty?

        # add price filter outside the query because it should have no effect on facets
        if price_min && price_max && (price_min < price_max)
          result[:filter] = { range: { price: { gte: price_min, lte: price_max } } }
        end

        result
      end
    end

    private

    def property_list
      product_properties.map{|pp| "#{pp.property.name}||#{pp.value}"}
    end
  end
end
