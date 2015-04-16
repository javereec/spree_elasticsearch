# encoding: UTF-8
Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree_elasticsearch'
  s.version     = '3.0.0'
  s.summary     = 'Add searching capabilities via Elasticsearch'
  s.description = s.summary
  s.required_ruby_version = '>= 1.9.3'

  s.author    = 'Jan Vereecken'
  s.email     = 'janvereecken@clubit.be'
  # s.homepage  = 'http://www.spreecommerce.com'

  #s.files       = `git ls-files`.split("\n")
  #s.test_files  = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_path = 'lib'
  s.requirements << 'none'

  s.add_dependency 'elasticsearch-model'
  s.add_dependency 'elasticsearch-rails'
  s.add_dependency 'settingslogic'
  s.add_dependency 'spree_core', '~> 3.0.0'
  s.add_dependency 'virtus'

  s.add_development_dependency 'capybara', '~> 2.1'
  s.add_development_dependency 'coffee-rails'
  s.add_development_dependency 'database_cleaner'
  s.add_development_dependency 'byebug'
  s.add_development_dependency 'factory_girl', '~> 4.2'
  s.add_development_dependency 'ffaker'
  s.add_development_dependency 'rspec-rails',  '~> 2.13'
  s.add_development_dependency 'sass-rails'
  s.add_development_dependency 'selenium-webdriver'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'sqlite3'
end
