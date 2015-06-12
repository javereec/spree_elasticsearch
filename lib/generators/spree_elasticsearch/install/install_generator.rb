module SpreeElasticsearch
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("../../templates", __FILE__)

      def add_javascripts
        append_file 'vendor/assets/javascripts/spree/frontend/all.js', "//= require spree/elasticsearch\n"
      end

      def add_stylesheets
        inject_into_file 'vendor/assets/stylesheets/spree/frontend/all.css', " *= require spree/elasticsearch\n", :before => /\*\//, :verbose => true
      end

      def copy_config
        template "elasticsearch.yml.sample", "config/elasticsearch.yml"
        template "index.yml.sample", "config/index.yml"
      end
    end
  end
end
