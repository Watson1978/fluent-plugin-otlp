# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "test-unit"
require 'fluent/test'
require 'fluent/test/helpers'
require 'json'

include Fluent::Test::Helpers

module Fluent::Plugin::Otlp
  module JSON
    # trim white spaces
    METRICS = ::JSON.generate(::JSON.parse(File.read(File.join(__dir__, "./fluent/assets/metrics.json"))))
    TRACES = ::JSON.parse(File.read(File.join(__dir__, "./fluent/assets/traces")))
  end
end