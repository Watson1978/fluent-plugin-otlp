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
        port 14318
      </http>
    CONFIG
  end

  def setup
    Fluent::Test.setup

    # Enable mock_process_clock for freezing Fluent::EventTime
    Timecop.mock_process_clock = true
    Timecop.freeze(Time.parse("2025-01-01 00:00:00 UTC"))
    @event_time = Fluent::EventTime.now
  end

  def teardown
    Timecop.mock_process_clock = false
    Timecop.return
  end

  def create_driver(conf = config)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::OtlpInput).configure(conf)
  end

  def test_configure
    d = create_driver
    assert_equal "otlp.test", d.instance.tag
    assert_equal "127.0.0.1", d.instance.http_config.bind
    assert_equal 14318, d.instance.http_config.port
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

    expected_events = [["otlp.test", @event_time, { type: data[:record_type], message: data[:record_data] }]]
    assert_equal(200, res.status)
    assert_equal(expected_events, d.events)
  end

  def test_receive_compressed_json
    d = create_driver
    res = d.run(expect_records: 1) do
      post_json("/v1/logs", compress(TestData::JSON::LOGS), headers: { "Content-Encoding" => "gzip" })
    end

    expected_events = [["otlp.test", @event_time, { type: "otlp_logs", message: TestData::JSON::LOGS }]]
    assert_equal(200, res.status)
    assert_equal(expected_events, d.events)
  end

  def test_invalid_json
    d = create_driver
    res = d.run(expect_records: 0) do
      post_json("/v1/logs", TestData::JSON::INVALID)
    end

    assert_equal(400, res.status)
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

    expected_events = [["otlp.test", @event_time, { type: data[:record_type], message: data[:record_data] }]]
    assert_equal(200, res.status)
    assert_equal(expected_events, d.events)
  end

  def test_receive_compressed_protocol_buffers
    d = create_driver
    res = d.run(expect_records: 1) do
      post_protobuf("/v1/logs", compress(TestData::ProtocolBuffers::LOGS), headers: { "Content-Encoding" => "gzip" })
    end

    expected_events = [["otlp.test", @event_time, { type: "otlp_logs", message: TestData::JSON::LOGS }]]
    assert_equal(200, res.status)
    assert_equal(expected_events, d.events)
  end

  def test_invalid_protocol_buffers
    d = create_driver
    res = d.run(expect_records: 0) do
      post_json("/v1/logs", TestData::ProtocolBuffers::INVALID)
    end

    assert_equal(400, res.status)
  end

  def test_invalid_content_type
    d = create_driver
    res = d.run(expect_records: 0) do
      post("/v1/logs", TestData::JSON::LOGS, headers: { "Content-Type" => "text/plain" })
    end

    assert_equal(415, res.status)
  end

  def test_invalid_content_encoding
    d = create_driver
    res = d.run(expect_records: 0) do
      post_json("/v1/logs", TestData::JSON::LOGS, headers: { "Content-Encoding" => "deflate" })
    end

    assert_equal(400, res.status)
  end

  sub_test_case "HTTPS" do
    def config
      <<~"CONFIG"
        tag otlp.test
        <http>
          bind 127.0.0.1
          port 14318
        </http>
        <transport tls>
          ca_path "#{File.expand_path(File.dirname(__FILE__) + '/../resources/certs/ca.crt')}"
          cert_path "#{File.expand_path(File.dirname(__FILE__) + '/../resources/certs/server.crt')}"
          private_key_path "#{File.expand_path(File.dirname(__FILE__) + '/../resources/certs/server.key')}"
          insecure true
        </transport>
      CONFIG
    end

    def test_https_receive_json
      d = create_driver
      res = d.run(expect_records: 1) do
        post_https_json("/v1/logs", TestData::JSON::LOGS)
      end

      expected_events = [["otlp.test", @event_time, { type: "otlp_logs", message: TestData::JSON::LOGS }]]
      assert_equal(200, res.status)
      assert_equal(expected_events, d.events)
    end

    def test_https_receive_protocol_buffers
      d = create_driver
      res = d.run(expect_records: 1) do
        post_https_protobuf("/v1/logs", TestData::ProtocolBuffers::LOGS)
      end

      expected_events = [["otlp.test", @event_time, { type: "otlp_logs", message: TestData::JSON::LOGS }]]
      assert_equal(200, res.status)
      assert_equal(expected_events, d.events)
    end
  end

  def compress(data)
    gz = Zlib::GzipWriter.new(StringIO.new)
    gz << data
    gz.close.string
  end

  def post_https_json(path, json, headers: {})
    headers = headers.merge({ "Content-Type" => "application/json" })
    post(path, json, endpoint: "https://127.0.0.1:14318", headers: headers, options: https_option)
  end

  def post_json(path, json, headers: {}, options: {})
    headers = headers.merge({ "Content-Type" => "application/json" })
    post(path, json, headers: headers, options: options)
  end

  def post_https_protobuf(path, binary, headers: {}, options: {})
    headers = headers.merge({ "Content-Type" => "application/x-protobuf" })
    post(path, binary, endpoint: "https://127.0.0.1:14318", headers: headers, options: options)
  end

  def post_protobuf(path, binary, headers: {}, options: {})
    headers = headers.merge({ "Content-Type" => "application/x-protobuf" })
    post(path, binary, headers: headers, options: options)
  end

  def post(path, body, endpoint: "http://127.0.0.1:14318", headers: {}, options: {})
    connection = Excon.new("#{endpoint}#{path}", body: body, headers: headers, **options)
    connection.post
  end

  def https_option
    Excon.defaults[:ssl_verify_peer] = false
    {
      client_cert: File.expand_path(File.dirname(__FILE__) + "/../resources/certs/ca.crt"),
      client_key: File.expand_path(File.dirname(__FILE__) + "/../resources/certs/ca.key")
    }
  end
end
