module Spree
  class ElasticsearchSettings < Settingslogic
    source "#{Rails.root}/config/elasticsearch.yml"
    namespace Rails.env
  end
end
