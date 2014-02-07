module Spree
  module Concerns
    module Indexable
      class ResultList
        include Enumerable

        attr_accessor :results
        attr_accessor :total
        attr_accessor :from

        def initialize(results, from, total)
          self.results = results
          self.from = from
          self.total = total
        end

        def each(*args, &block)
          results.each(*args, &block)
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

          result_list = result["hits"]["hits"].map do |item|
            object_attributes = item["_source"]
            object_attributes.except!(*exclude_from_response)
            model = new(object_attributes)
            model.version = item["_version"]
            model
          end

          ResultList.new(result_list, Integer(args.fetch(:from, 0)), result["hits"]["total"])
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

        result = client.index id: id,
                              type: type,
                              index: configuration.index,
                              body: doc

        unless result['ok']
          raise "Indexing Error: #{result.inspect}"
        end

        result
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