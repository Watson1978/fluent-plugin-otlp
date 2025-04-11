# frozen_string_literal: true

require "helper"

require "fluent/plugin/out_otlp"
require "fluent/test/driver/output"

require "webrick"

class Fluent::Plugin::OtlpOutputTest < Test::Unit::TestCase
  ServerRequest = Struct.new(:request_method, :path, :header, :body)

  DEFAULT_LOGGER = ::WEBrick::Log.new($stdout, ::WEBrick::BasicLog::FATAL)

  def config
    <<~CONFIG
      <http>
        endpoint "http://127.0.0.1:4318"
      </http>
    CONFIG
  end

  def server_config
    config = { BindAddress: "127.0.0.1", Port: "4318" }
    # Suppress webrick logs
    config[:Logger] = DEFAULT_LOGGER
    config[:AccessLog] = []
    config
  end

  def run_http_server
    server = ::WEBrick::HTTPServer.new(server_config)
    server.mount_proc("/v1/metrics") do |req, res|
      @@server_request = ServerRequest.new(req.request_method.dup, req.path.dup, req.header.dup, req.body.dup)
      res.status = 200
    end
    server.mount_proc("/v1/traces") do |req, res|
      @@server_request = ServerRequest.new(req.request_method.dup, req.path.dup, req.header.dup, req.body.dup)
      res.status = 200
    end
    server.mount_proc("/v1/logs") do |req, res|
      @@server_request = ServerRequest.new(req.request_method.dup, req.path.dup, req.header.dup, req.body.dup)
      res.status = 200
    end
    server.start
  ensure
    begin
      server.shutdown
    rescue StandardError
      nil
    end
  end

  def setup
    Fluent::Test.setup

    @@server_request = nil
    @@http_server_thread ||= Thread.new do
      run_http_server
    end
  end

  def teardown
    @@server_request = nil
  end

  def create_driver(conf = config)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::OtlpOutput).configure(conf)
  end

  def test_configure
    d = create_driver
    assert_equal "http://127.0.0.1:4318", d.instance.http_config.endpoint
  end

  def test_send_logs
    event = { "type" => "otlp_logs", "message" => TestData::JSON::LOGS }

    d = create_driver
    d.run(default_tag: "otlp.test") do
      d.feed(event)
    end

    assert_equal("/v1/logs", @@server_request.path)
    assert_equal("POST", @@server_request.request_method)
    assert_equal(["application/x-protobuf"], @@server_request.header["content-type"])
    assert_equal(TestData::ProtocolBuffers::LOGS, @@server_request.body)
  end

  def test_send_metrics
    event = { "type" => "otlp_metrics", "message" => TestData::JSON::METRICS }

    d = create_driver
    d.run(default_tag: "otlp.test") do
      d.feed(event)
    end

    assert_equal("/v1/metrics", @@server_request.path)
    assert_equal("POST", @@server_request.request_method)
    assert_equal(["application/x-protobuf"], @@server_request.header["content-type"])
    assert_equal(TestData::ProtocolBuffers::METRICS, @@server_request.body)
  end

  def test_send_traces
    event = { "type" => "otlp_traces", "message" => TestData::JSON::TRACES }

    d = create_driver
    d.run(default_tag: "otlp.test") do
      d.feed(event)
    end

    assert_equal("/v1/traces", @@server_request.path)
    assert_equal("POST", @@server_request.request_method)
    assert_equal(["application/x-protobuf"], @@server_request.header["content-type"])
    assert_equal(TestData::ProtocolBuffers::TRACES, @@server_request.body)
  end

  def test_send_compressed_message
    event = { "type" => "otlp_logs", "message" => TestData::JSON::LOGS }

    d = create_driver(config + "compress gzip")
    d.run(default_tag: "otlp.test") do
      d.feed(event)
    end

    assert_equal("/v1/logs", @@server_request.path)
    assert_equal("POST", @@server_request.request_method)
    assert_equal(["application/x-protobuf"], @@server_request.header["content-type"])
    assert_equal(["gzip"], @@server_request.header["content-encoding"])
    assert_equal(TestData::ProtocolBuffers::LOGS, decompress(@@server_request.body).force_encoding(Encoding::ASCII_8BIT))
  end

  def decompress(data)
    Zlib::GzipReader.new(StringIO.new(data)).read
  end
end
