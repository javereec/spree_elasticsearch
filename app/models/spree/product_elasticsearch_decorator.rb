module Spree
  Product::ElasticsearchQuery.class_eval do
    def to_hash
      q = { match_all: {} }
      # search for ean13 code in search string
      query.scan

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
      # only return products that are available
      and_filter << { range: { available_on: { lte: "now" } } }
      result[:query][:filtered][:filter] = { "and" => and_filter } unless and_filter.empty?

      # add price filter outside the query because it should have no effect on facets
      if price_min && price_max && (price_min < price_max)
        result[:filter] = { range: { price: { gte: price_min, lte: price_max } } }
      end

      result
    end
  end
end
