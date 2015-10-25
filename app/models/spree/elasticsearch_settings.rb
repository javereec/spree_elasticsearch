module Spree
  class ElasticsearchSettings < Settingslogic
    def self.config_file
      path = "#{Rails.root}/config/elasticsearch.yml"
      return path if File.exists?(path)

      File.open(path, "w") do |file|
        file.puts(default_config)
      end
      path
    end

    def self.default_config
      <<-EOS
defaults: &defaults
  hosts: ["127.0.0.1:9200"]
  bootstrap: true

development:
  <<: *defaults
  index: development

test:
  <<: *defaults
  index: test

production:
  <<: *defaults
  index: production
      EOS
    end

    source config_file
    namespace Rails.env
  end
end
