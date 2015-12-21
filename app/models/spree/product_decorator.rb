module Spree
  Product.class_eval do
    include Elasticsearch::Model

    index_name Spree::ElasticsearchSettings.index
    document_type 'spree_product'

    mapping _all: {"index_analyzer" => "nGram_analyzer", "search_analyzer" => "whitespace_analyzer"} do
      indexes :name, type: 'multi_field' do
        indexes :name, type: 'string', analyzer: 'nGram_analyzer', boost: 100
        indexes :untouched, type: 'string', include_in_all: false, index: 'not_analyzed'
      end
      indexes :description, analyzer: 'snowball'
      indexes :available_on, type: 'date', format: 'dateOptionalTime', include_in_all: false
      indexes :price, type: 'double'
      indexes :sku, type: 'string', index: 'not_analyzed'
      indexes :taxon_ids, type: 'string', index: 'not_analyzed'
      indexes :taxon_names, analyzer: 'snowball'
      indexes :properties, type: 'string', index: 'not_analyzed'
      indexes :variants do
        indexes :option_values do
          indexes :id, type: 'string', index: 'not_analyzed'
        end
      end
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
                only: [:id, :name, :presentation]
              }
            }
          }
        }
      })
      result[:properties] = property_list unless property_list.empty?

      if taxons.present?
        taxon_with_children = taxons.map(&:self_and_ancestors).flatten.uniq

        result[:taxon_ids] = taxon_with_children.map(&:id)
        result[:taxon_names] = taxon_with_children.map(&:name)
      end
      result
    end

    # Inner class used to query elasticsearch. The idea is that the query is dynamically build based on the parameters.
    class Product::ElasticsearchQuery
      include ::Virtus.model

      attribute :from, Integer, default: 0
      attribute :price_min, Float
      attribute :price_max, Float
      attribute :properties, Hash
      attribute :query, String
      attribute :taxon, String
      attribute :taxons, Hash
      attribute :option_types, Hash
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
      #           { bool: { must: [{term: {taxon_ids: []}}] } },
      #           { terms: { properties: [] } }
      #         ]
      #       }
      #     }
      #   }
      #   filter: { range: { price: { lte: , gte: } } },
      #   sort: [],
      #   from: ,
      #   facets:
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
          properties = @properties.map {|k,v| [k].product(v)}.map do |pair|
            and_filter << { terms: { properties: pair.map {|prop| prop.join("||")} } }
          end
        end

        sorting = case @sorting
        when "name_asc"
          [ {"name.untouched" => { order: "asc" }}, {"price" => { order: "asc" }}, "_score" ]
        when "name_desc"
          [ {"name.untouched" => { order: "desc" }}, {"price" => { order: "asc" }}, "_score" ]
        when "price_asc"
          [ {"price" => { order: "asc" }}, {"name.untouched" => { order: "asc" }}, "_score" ]
        when "price_desc"
          [ {"price" => { order: "desc" }}, {"name.untouched" => { order: "asc" }}, "_score" ]
        when "score"
          [ "_score", {"name.untouched" => { order: "asc" }}, {"price" => { order: "asc" }} ]
        else
          [ {"name.untouched" => { order: "asc" }}, {"price" => { order: "asc" }}, "_score" ]
        end

        # facets
        facets = {
          price: { statistical: { field: "price" } },
          properties: { terms: { field: "properties", order: "count", size: 1000000 } },
          taxon_ids: { terms: { field: "taxon_ids", size: 1000000 } }
        }

        # basic skeleton
        result = {
          min_score: 0.1,
          query: { filtered: {} },
          sort: sorting,
          from: from,
          facets: facets,
          fields: ["_id"]
        }

        # add query and filters to filtered
        result[:query][:filtered][:query] = query

        if taxon.present?
          and_filter << {
            bool: {
              must: [{term: {taxon_ids: taxon}}]
            }
          }
        end

        # option_type, taxon and property filters have an effect on the facets
        if option_types.present?
          option_types.each do |option_type_id, option_value_ids|
            and_filter << {bool: {must: [{ term: { "variants.option_values.id" => option_value_ids }}]}}
          end
        end

        if taxons.present?
          taxons.each do |taxonomy_id, taxon_ids|
            and_filter << {bool: {must: [{ term: { taxon_ids: taxon_ids }}]}}
          end
        end

        # only return products that are available
        and_filter << { range: { available_on: { lte: "now" } } }
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
