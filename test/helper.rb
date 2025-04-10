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
    METRICS = ::JSON.generate(::JSON.parse(File.read(File.join(__dir__, "./fluent/assets/metrics.json"))))
    TRACES = ::JSON.generate(::JSON.parse(File.read(File.join(__dir__, "./fluent/assets/traces.json"))))
    LOGS = ::JSON.generate(::JSON.parse(File.read(File.join(__dir__, "./fluent/assets/logs.json"))))
  end

  module ProtocolBuffers
    METRICS = Fluent::Plugin::Otlp::Request::Metrics.new(TestData::JSON::METRICS).encode
    TRACES = Fluent::Plugin::Otlp::Request::Traces.new(TestData::JSON::TRACES).encode
    LOGS = Fluent::Plugin::Otlp::Request::Logs.new(TestData::JSON::LOGS).encode
  end
end
