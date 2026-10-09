# frozen_string_literal: true

# Test entry point: loads the harness, discovers every *_test.rb and runs it.
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift File.expand_path('..', __dir__)

begin
  require 'simplecov'
  SimpleCov.start do
    add_filter '/test/'
    track_files '{lib,app/controllers/redmine_oidc}/**/*.rb'
    minimum_coverage 80
  end
rescue LoadError
  # Coverage is optional; the CI image provides simplecov.
end

require 'minitest/autorun'
require_relative 'test_helper'

Dir[File.expand_path('unit/**/*_test.rb', __dir__)].sort.each { |file| require file }
