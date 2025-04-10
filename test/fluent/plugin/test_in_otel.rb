# frozen_string_literal: true

require "helper"

require "fluent/plugin/in_otlp"
require "fluent/test/driver/input"

class Fluent::Plugin::OtlpInputTest < Test::Unit::TestCase
  def config
    <<~CONFIG
      tag otlp.test
      <http>
        bind 127.0.0.1
        port 4318
      </http>
    CONFIG
  end

  def setup
    Fluent::Test.setup
  end

  def create_driver(conf = config)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::OtlpInput).configure(conf)
  end

  def test_configure
    d = create_driver
    assert_equal "otlp.test", d.instance.tag
    assert_equal "127.0.0.1", d.instance.http_config.bind
    assert_equal 4318, d.instance.http_config.port
  end

  data("metrics" => {
         request_path: "/v1/metrics",
         request_data: TestData::JSON::METRICS,
         record_type: "otlp_metrics",
         record_data: TestData::JSON::METRICS
       },
       "traces" => {
         request_path: "/v1/traces",
         request_data: TestData::JSON::TRACES,
         record_type: "otlp_traces",
         record_data: TestData::JSON::TRACES
       },
       "logs" => {
         request_path: "/v1/logs",
         request_data: TestData::JSON::LOGS,
         record_type: "otlp_logs",
         record_data: TestData::JSON::LOGS
       })
  def test_receive_json(data)
    d = create_driver
    res = d.run(expect_records: 1) do
      post_json(data[:request_path], data[:request_data])
    end

    assert_equal(200, res.status)
    assert_equal("otlp.test", d.events[0][0])
    assert_equal({ type: data[:record_type], message: data[:record_data] }, d.events[0][2])
  end

  def test_receive_compressed_json
    d = create_driver
    res = d.run(expect_records: 1) do
      post_json("/v1/metrics", compress(TestData::JSON::METRICS), { "Content-Encoding" => "gzip" })
    end

    assert_equal(200, res.status)
    assert_equal("otlp.test", d.events[0][0])
    assert_equal({ type: "otlp_metrics", message: TestData::JSON::METRICS }, d.events[0][2])
  end

  data("metrics" => {
         request_path: "/v1/metrics",
         request_data: TestData::ProtocolBuffers::METRICS,
         record_type: "otlp_metrics",
         record_data: TestData::JSON::METRICS
       },
       "traces" => {
         request_path: "/v1/traces",
         request_data: TestData::ProtocolBuffers::TRACES,
         record_type: "otlp_traces",
         record_data: TestData::JSON::TRACES
       },
       "logs" => {
         request_path: "/v1/logs",
         request_data: TestData::ProtocolBuffers::LOGS,
         record_type: "otlp_logs",
         record_data: TestData::JSON::LOGS
       })
  def test_receive_protocol_buffers(data)
    d = create_driver
    res = d.run(expect_records: 1) do
      post_protobuf(data[:request_path], data[:request_data])
    end

    assert_equal(200, res.status)
    assert_equal("otlp.test", d.events[0][0])
    assert_equal({ type: data[:record_type], message: data[:record_data] }, d.events[0][2])
  end

  def test_receive_compressed_protocol_buffers
    d = create_driver
    res = d.run(expect_records: 1) do
      post_json("/v1/metrics", compress(TestData::ProtocolBuffers::METRICS), { "Content-Encoding" => "gzip" })
    end

    assert_equal(200, res.status)
    assert_equal("otlp.test", d.events[0][0])
    assert_equal({ type: "otlp_metrics", message: TestData::JSON::METRICS }, d.events[0][2])
  end

  def compress(data)
    gz = Zlib::GzipWriter.new(StringIO.new)
    gz << data
    gz.close.string
  end

  def post_json(path, json, headers = {})
    headers = headers.merge({ "Content-Type" => "application/json" })
    post(path, json, headers)
  end

  def post_protobuf(path, binary, headers = {})
    headers = headers.merge({ "Content-Type" => "application/x-protobuf" })
    post(path, binary, headers)
  end

  def post(path, body, headers = {})
    connection = Excon.new("http://127.0.0.1:4318#{path}", body: body, headers: headers)
    connection.post
  end
end
