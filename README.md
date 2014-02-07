# SpreeElasticsearch

This extension uses elasticsearch-ruby for integration of Elasticsearch with Spree. While you can use this as configured.

## Installation

Add spree_elasticsearch to your Gemfile:

```ruby
gem 'spree_elasticsearch'
```

Bundle your dependencies and run the installation generator:

```shell
bundle
bundle exec rails g spree_elasticsearch:install
```

Edit the file in `config\elasticsearch.yml` to match your configuration.

### Elasticsearch

Elasticsearch is very easy to install. Get and unzip elasticsearch 0.90.x: http://www.elasticsearch.org/download

Start:

```shell
bin/elasticsearch -f
```

Execute following to drop index (all) and have a fresh start:

```shell
curl -XDELETE 'http://localhost:9200'
```

## Testing

Be sure to bundle your dependencies and then create a dummy test app for the specs to run against.

```shell
bundle
bundle exec rake test_app
bundle exec rspec spec
```

When testing your applications integration with this extension you may use it's factories.
Simply add this require statement to your spec_helper:

```ruby
require 'spree_elasticsearch/factories'
```

Copyright (c) 2014 Jan Vereecken, released under the New BSD License
