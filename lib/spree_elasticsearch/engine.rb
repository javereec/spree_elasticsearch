module SpreeElasticsearch
  class Engine < Rails::Engine
    require 'spree/core'
    isolate_namespace Spree
    engine_name 'spree_elasticsearch'

    config.autoload_paths += %W(#{config.root}/lib)

    # use rspec for tests
    config.generators do |g|
      g.test_framework :rspec
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*_decorator*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    config.to_prepare &method(:activate).to_proc

    config.after_initialize do
      begin
        if Spree::ElasticsearchSettings.bootstrap
          client = Elasticsearch::Client.new log: true, hosts: Spree::ElasticsearchSettings.hosts
          # create the index, but continue when it already exists
          begin
            client.indices.create index: Spree::ElasticsearchSettings.index, body: { }
          rescue Elasticsearch::Transport::Transport::Errors::BadRequest
          end
          # create or update all mappings on the index
          client.indices.put_mapping index: Spree::ElasticsearchSettings.index, type: Spree::Product.type, body: Spree::Product.mapping
        end
      rescue Errno::ENOENT
        Rails.logger.error "The file config/elasticsearch.yml was not found. Please install with bundle exec rails g spree_elasticsearch:install."
      end
    end
  end
end
