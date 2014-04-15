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
      #         terms: { taxons: [] }
      #       }
      #     }
      #   }
      #   filter: { and: [ { terms: { properties: [] } } ] }
      #   sort: [],
      #   from: ,
      #   size: ,
      #   facets:
      # }
      def to_hash
        q = { match_all: {} }
        if query # search in name and description
          q = { query_string: { query: query, fields: ['name^5','description'], use_dis_max: true } }
        end        
        query = q

        and_filter = []
        if price_min && price_max && (price_min < price_max)
          and_filter << { range: { price: { gte: price_min, lte: price_max } } }
        end
        unless @properties.nil? || @properties.empty?
          # transform properties from [{"key1" => ["value_a","value_b"]},{"key2" => ["value_a"]} 
          # to { terms: { properties: ["key1||value_a","key1||value_b"] }
          #    { terms: { properties: ["key2||value_a"] }
          # This enforces "and" relation between different property values and "or" relation between same property values
          properties = @properties.map {|k,v| [k].product(v)}.map do |pair| 
            and_filter << { terms: { properties: pair.map {|prop| prop.join("||")} } }
          end
        end

        sorting = [ name: { order: "asc" } ]

        # facets
        facets = {
          price: { statistical: { field: "price" } },
          properties: { terms: { field: "properties", order: "reverse_count", size: 1000000 } } 
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
        result[:query][:filtered][:filter] = { terms: { taxons: taxons } } unless taxons.empty?

        # add price / property filter
        result[:filter] = { "and" => and_filter } unless and_filter.empty?

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
        name: { type: 'string', analyzer: 'snowball', boost: 100 },
        description: { type: 'string', analyzer: 'snowball' },
        available_on: { type: 'date', format: 'dateOptionalTime', include_in_all: false },
        updated_at: { type: 'date', format: 'dateOptionalTime', include_in_all: false },
        price: { type: 'double' },
        properties: { type: 'string', index: 'not_analyzed'},
        taxons: { type: 'string', index: 'not_analyzed' }
      }
    end

    #
    def cache_key
      if elasticsearch_index # elasticsearch attribute
        timestamp = updated_at.try(:utc).try(:to_s,:nsec) # nsec is default cache key format (https://github.com/rails/rails/blob/4-0-stable/activerecord/lib/active_record/integration.rb)
        return "#{self.class.model_name.cache_key}/#{id}-#{timestamp}"
      end
      case
      when new_record?
        "#{self.class.model_name.cache_key}/new"
      when timestamp = max_updated_column_timestamp
        timestamp = timestamp.utc.to_s(cache_timestamp_format)
        "#{self.class.model_name.cache_key}/#{id}-#{timestamp}"
      else
        "#{self.class.model_name.cache_key}/#{id}"
      end
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
      result['properties'] = product_properties.map{|pp| "#{pp.property.name}||#{pp.value}"} unless product_properties.empty?
      result['taxons'] = taxons.map(&:name) unless taxons.empty?
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
      if available?
        self.index
      end
      if deleted?
        self.remove_from_index
      end
    end
  end
end