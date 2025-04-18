# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "fluent/plugin/otlp/request"
require "fluent/test"
require "fluent/test/helpers"

require "excon"
require "json"
require "stringio"
require "test-unit"
require "timecop"
require "zlib"

include Fluent::Test::Helpers

module TestData
  module JSON
    # trim white spaces
    METRICS = ::JSON.generate(::JSON.parse(File.read(File.join(__dir__, "./fluent/resources/data/metrics.json"))))
    TRACES = ::JSON.generate(::JSON.parse(File.read(File.join(__dir__, "./fluent/resources/data/traces.json"))))
    LOGS = ::JSON.generate(::JSON.parse(File.read(File.join(__dir__, "./fluent/resources/data/logs.json"))))

    INVALID = '{"resourceMetrics": "invalid"}'
  end

  module ProtocolBuffers
    METRICS = Fluent::Plugin::Otlp::Request::Metrics.new(TestData::JSON::METRICS).body
    TRACES = Fluent::Plugin::Otlp::Request::Traces.new(TestData::JSON::TRACES).body
    LOGS = Fluent::Plugin::Otlp::Request::Logs.new(TestData::JSON::LOGS).body

    INVALID = "invalid"
  end
end
