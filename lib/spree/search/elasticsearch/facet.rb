module Spree
  module Search
    class Elasticsearch::Facet
      include ::Virtus.model

      attribute :name, String
      attribute :search_name, String # name for input in elasticsearch query
      attribute :type, String
      attribute :body, Hash
    end
  end
end