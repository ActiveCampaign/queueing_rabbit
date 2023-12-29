$:.unshift File.expand_path('..', __FILE__)
$:.unshift File.expand_path('../../lib', __FILE__)

require 'rubygems'
require 'bundler'
Bundler.setup(:test)

require 'rspec'
require 'rspec/its'
require 'rspec/autorun'
require 'eventmachine'
require 'evented-spec'
require 'support/shared_contexts'

require 'queueing_rabbit'

RSpec.configure do |config|
  config.exclusion_filter = {
    :ruby => RUBY_VERSION
  }
end
