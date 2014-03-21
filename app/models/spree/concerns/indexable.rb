module Spree
  module Concerns
    module Indexable
      class ResultList
        include Enumerable
        include Kaminari::PageScopeMethods
        include ::Virtus.model

        attribute :results, Array
        attribute :total, Integer
        attribute :from, Integer
        attribute :facets, Array

        def each(*args, &block)
          results.each(*args, &block)
        end

        def empty?
          count == 0
        end

        # Kaminari pagination support

        def limit_value
          Spree::Config.products_per_page
        end

        def offset_value
          from
        end

        def total_count
          total
        end

        def max_pages
          nil
        end

        # Spree cache_key_for_products support

        def maximum(column)
          results.max {|a,b| a.send(column) <=> b.send(column)}.send(column)
        end
      end

      extend ActiveSupport::Concern

      included do
        attr_accessor :version
        after_save :update_index
        after_destroy :update_index
      end

      module ClassMethods
        def client
          @client ||= Elasticsearch::Client.new log: true, hosts: configuration.hosts
        end

        def configuration
          ElasticsearchSettings
        end

        def delete_all
          begin
            client.perform_request 'DELETE', configuration.index
          rescue => e
            # Throws exception if the index doesn't exist
          end
        end

        # Get a document in Elasticsearch based on id
        def get(id)
          result = client.get id: id,
                              type: type,
                              index: configuration.index
          object_attributes = result["_source"]
          object_attributes.except!(*exclude_from_response)
          model = self.new(object_attributes)
          model.version = result["_version"]
          model
        end

        # Used during initialization of the application to create or update the mapping.
        # The actual implementation of the mapping is defined in the models.
        def mapping
          {
            type.to_sym => {
              properties: self.type_mapping
            }
          }
        end

        # The actual searching in Elasticsearch.
        def search(args = {})
          search_args = {}
          search_args[:body] = self::ElasticsearchQuery.new(args).to_hash
          search_args[:index] = configuration.index
          search_args[:type] = type

          result = client.search search_args

          # Convert all results to objects using the information in the _source.
          result_list = result["hits"]["hits"].map do |item|
            object_attributes = item["_source"]
            object_attributes.except!(*exclude_from_response)
            # model = find(object_attributes["id"]) # get the record from the database
            model = new(object_attributes) # instantiate record to avoid selection in spree_products
            model.version = item["_version"]
            model
          end

          # Convert all facets to facet objects
          facet_list = result["facets"].map do |tuple|
            name = tuple[0]
            hash = tuple[1]
            type = hash["_type"]
            body = hash.except!("_type")
            Spree::Search::Elasticsearch::Facet.new(name: name, search_name: name, type: type, body: body)
          end

          ResultList.new(
            results: result_list,
            from: Integer(args.fetch(:from, 0)),
            total: result["hits"]["total"],
            facets: facet_list
          )
        end

        def type
          name.underscore.gsub('/','_')
        end
      end

      def client
        self.class.client
      end

      def configuration
        self.class.configuration
      end

      def remove_from_index
        client.delete id: id,
                      type: type,
                      index: configuration.index
      end

      def index
        doc = to_hash
        doc.delete(:id)
        doc.delete(:version)

        client.index id: id,
                     type: type,
                     index: configuration.index,
                     body: doc
      end

      def type
        self.class.type
      end

      def update_index
        self.index
      end
    end
  end
end