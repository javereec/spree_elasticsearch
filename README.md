# Spree Elasticsearch

This extension uses elasticsearch-ruby for integration of Elasticsearch with Spree. This is preconfigured for a certain use case, but by all means override where necessary.

To understand what is going on, you should first learn about Elasticsearch. Some great resources:

* http://exploringelasticsearch.com is an excellent introduction to Elasticsearch
* http://elastichammer.exploringelasticsearch.com/ is a tool to test queries against your own Elasticsearch cluster
* https://www.found.no/play/ is an another online tool that can be used to play with Elasticsearch. The online version communicates with an online cluster run by Found.

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

Edit/create the file in `config/elasticsearch.yml` to match your configuration.

Edit the spree initializer in `config/initializers/spree.rb` and use the elasticsearch searcher.

```ruby
Spree.config do |config|
  config.searcher_class = Spree::Search::Elasticsearch
end
```

Create a decorator for Product model to implement callbacks and update the index. Check the [elasticsearch-rails](https://github.com/elasticsearch/elasticsearch-rails/tree/master/elasticsearch-model#updating-the-documents-in-the-index) documentation for different options.

For example using the model callbacks

```ruby
module Spree
  Product.class_eval do
    include Elasticsearch::Model::Callbacks  
  end
end
```

### Elasticsearch

Elasticsearch is very easy to install. Get and unzip elasticsearch 1.x.x: http://www.elasticsearch.org/download

Start:

```shell
bin/elasticsearch
```

Execute following to drop index (all) and have a fresh start:

```shell
curl -XDELETE 'http://localhost:9200'
```

Elasticsearch has a nifty plugin, called Marvel, you can install to view the status of the cluster, but which can also serve as a tool to debug the commands you're running against the cluser. This tool is free for development purposes, but requires a license for production environments. You can install it by executing the following.

```shell
bin/plugin -i elasticsearch/marvel/latest
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
