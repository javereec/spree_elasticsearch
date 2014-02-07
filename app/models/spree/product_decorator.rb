module Spree
  Product.class_eval do
    # Inner class used to query elasticsearch. The idea is that the query is dynamically build based on the parameters.
    class Product::ElasticsearchQuery
      include ::Virtus.model

      attribute :name, String
      attribute :description, String
      attribute :available_on, DateTime
      attribute :price, Array
      attribute :properties, Hash
      attribute :taxons, Array

      # Method that creates the actual query based on the current attributes.
      # The idea is to always to use the following schema and fill in the blanks.
      # {
      #   query: {
      #     filtered: {
      #       query: {
      #         must: { match: [] }
      #       }
      #       filter: {
      #         and: []
      #       }
      #     }
      #   }
      # }
      def to_hash
        must_matches = []
        if name
          must_matches << { match: { name: name } }
        end
        unless properties.empty?
          # transform properties to array of match definitions
          properties.map do |k,v|
            must_matches << { match: { "properties.#{k}" => v } }
          end
        end
        must_matches << { match_all: {} } if must_matches.empty?
        query = { bool: { must: must_matches } }

        and_filter = []
        unless taxons.empty?
          and_filter << { terms: { taxons: taxons } }
        end

        unless price.empty?
          and_filter << { range: { price: { gte: price[0], lt: price[1] } } }
        end

        sorting = [ name: { order: "asc" } ]

        # basic skeleton
        result = {
          query: { filtered: { } },
          sort: sorting
        }
        # add query and filters to filtered
        result[:query][:filtered][:query] = query unless query.nil?
        result[:query][:filtered][:filter] = { "and" => and_filter } unless and_filter.empty?
        result
      end
    end

    include Concerns::Indexable

    # Excluse following keys when retrieving something from the Elasticsearch response
    def self.exclude_from_response
      ['properties']
    end

    # Used at startup when creating or updating the index with all type mappings
    def self.type_mapping
      {
        id: { type: 'string', index: 'not_analyzed' },
        name: { type: 'string', analyzer: 'snowball', boost: 100 },
        description: { type: 'string', analyzer: 'snowball' },
        available_on: { type: 'date', format: 'dateOptionalTime', include_in_all: false },
        price: { type: 'double' },
        taxons: { type: 'string', index: 'not_analyzed' }
      }
    end

    # Put all properties of a product in a hash. The key is the name of the property.
    def properties_to_hash
      result = {}
      self.product_properties.each{|pp| result[pp.property.name] = pp.value}
      result
    end

    # Used when creating or updating a document in the index
    def to_hash
      result = {
        'id' => id,
        'name' => name,
        'description' => description,
        'available_on' => available_on,
        'price' => price,
      }
      # debugger
      result['properties'] = properties_to_hash unless properties_to_hash.empty?
      result['taxons'] = taxons.to_a unless taxons.empty?
      result
    end

    # Override from concern for better control.
    # If the product is available, index. If the product is destroyed (deleted_at attribute is set), delete from index.
    def update_index
      if available?
        self.index
      end
      if deleted?
        self.remove_from_index
      end
    end
  end
end