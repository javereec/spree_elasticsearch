module Spree
  Product.class_eval do
    # Inner class used to query elasticsearch. The idea is that the query is dynamically build based on the parameters.
    class Product::ElasticsearchQuery
      include ::Virtus.model

      attribute :from, Integer, default: 0
      attribute :price_min, Float
      attribute :price_max, Float
      attribute :properties, Hash
      attribute :query, String
      attribute :taxons, Array

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
      #   size: ,
      #   facets:
      # }
      def to_hash
        q = { match_all: {} }
        if query # search in name and description
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

        sorting = [ "name.untouched" => { order: "asc" } ]

        # facets
        facets = {
          price: { statistical: { field: "price" } },
          properties: { terms: { field: "properties", order: "count", size: 1000000 } },
          taxons: { terms: { field: "taxons", size: 1000000 } }
        }

        # basic skeleton
        result = {
          query: { filtered: {} },
          sort: sorting,
          from: from,
          size: Spree::Config.products_per_page,
          facets: facets
        }

        # add query and filters to filtered
        result[:query][:filtered][:query] = query
        # taxon and property filters have an effect on the facets
        and_filter << { terms: { taxons: taxons } } unless taxons.empty?
        result[:query][:filtered][:filter] = { "and" => and_filter } unless and_filter.empty?

        # add price filter outside the query because it should have no effect on facets
        if price_min && price_max && (price_min < price_max)
          result[:filter] = { range: { price: { gte: price_min, lte: price_max } } }
        end

        result
      end
    end

    include Concerns::Indexable

    # Exclude following keys when retrieving something from the Elasticsearch response.
    def self.exclude_from_response
      ['properties','taxons','variants']
    end

    # Used at startup when creating or updating the index with all type mappings
    def self.type_mapping
      {
        id: { type: 'string', index: 'not_analyzed' },
        name: {
          fields: {
            name: { type: 'string', analyzer: 'snowball', boost: 100 },
            untouched: { include_in_all: false, index: "not_analyzed", type: "string" }
          },
          type: "multi_field"
        },
        description: { type: 'string', analyzer: 'snowball' },
        available_on: { type: 'date', format: 'dateOptionalTime', include_in_all: false },
        updated_at: { type: 'date', format: 'dateOptionalTime', include_in_all: false },
        price: { type: 'double' },
        properties: { type: 'string', index: 'not_analyzed' },
        sku: { type: 'string', index: 'not_analyzed' },
        taxons: { type: 'string', index: 'not_analyzed' }
      }
    end

    # Used when creating or updating a document in the index
    def to_hash
      result = {
        'id' => id,
        'name' => name,
        'description' => description,
        'available_on' => available_on,
        'updated_at' => updated_at,
        'price' => price,
      }
      result['sku'] = sku unless sku.try(:empty?)
      result['properties'] = product_properties.map{|pp| "#{pp.property.name}||#{pp.value}"} unless product_properties.empty?
      unless taxons.empty?
        # in order for the term facet to be correct we should always include the parent taxon(s)
        result['taxons'] = taxons.map do |taxon|
          taxon.self_and_ancestors.map(&:permalink)
        end.flatten
      end
      # add variants information
      if variants.length > 0
        result['variants'] = []
        variants.each do |variant|
          result['variants'] << variant.attributes
        end
      end
      result
    end

    # Override from concern for better control.
    # If the product is available, index. If the product is destroyed (deleted_at attribute is set), delete from index.
    def update_index
      begin
        if available?
          self.index
        end
        if deleted?
          self.remove_from_index
        end
      rescue Elasticsearch::Transport::Transport::Errors => e
        Rails.logger.error e
      end
    end
  end
end