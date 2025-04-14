# frozen_string_literal: true

require "helper"

require "fluent/plugin/out_otlp"
require "fluent/test/driver/output"

require "webrick"
require "webrick/https"

class Fluent::Plugin::OtlpOutputTest < Test::Unit::TestCase
  ServerRequest = Struct.new(:request_method, :path, :header, :body)

  DEFAULT_LOGGER = ::WEBrick::Log.new($stdout, ::WEBrick::BasicLog::FATAL)

  def config
    <<~CONFIG
      <http>
        endpoint "http://127.0.0.1:14318"
      </http>
    CONFIG
  end

  def server_config
    config = { BindAddress: "127.0.0.1", Port: "14318" }
    # Suppress webrick logs
    config[:Logger] = DEFAULT_LOGGER
    config[:AccessLog] = []
    config
  end

  def server_request
    @@server_request
  end

  def server_response_code(code)
    @@server_response_code = code
  end

  def run_http_server
    server = ::WEBrick::HTTPServer.new(server_config)
    server.mount_proc("/v1/metrics") do |req, res|
      @@server_request = ServerRequest.new(req.request_method.dup, req.path.dup, req.header.dup, req.body.dup)
      res.status = @@server_response_code
    end
    server.mount_proc("/v1/traces") do |req, res|
      @@server_request = ServerRequest.new(req.request_method.dup, req.path.dup, req.header.dup, req.body.dup)
      res.status = @@server_response_code
    end
    server.mount_proc("/v1/logs") do |req, res|
      @@server_request = ServerRequest.new(req.request_method.dup, req.path.dup, req.header.dup, req.body.dup)
      res.status = @@server_response_code
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
    @@server_response_code = 200
    @@http_server_thread = Thread.new do
      run_http_server
    end
  end

  def teardown
    @@server_request = nil
    @@server_response_code = 200
    @@http_server_thread.kill
    @@http_server_thread = nil
  end

  def create_driver(conf = config)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::OtlpOutput).configure(conf)
  end

  def test_configure
    d = create_driver
    assert_equal "http://127.0.0.1:14318", d.instance.http_config.endpoint
  end

  def test_send_logs
    event = { "type" => "otlp_logs", "message" => TestData::JSON::LOGS }

    d = create_driver
    d.run(default_tag: "otlp.test") do
      d.feed(event)
    end

    assert_equal("/v1/logs", server_request.path)
    assert_equal("POST", server_request.request_method)
    assert_equal(["application/x-protobuf"], server_request.header["content-type"])
    assert_equal(TestData::ProtocolBuffers::LOGS, server_request.body)
  end

  def test_send_metrics
    event = { "type" => "otlp_metrics", "message" => TestData::JSON::METRICS }

    d = create_driver
    d.run(default_tag: "otlp.test") do
      d.feed(event)
    end

    assert_equal("/v1/metrics", server_request.path)
    assert_equal("POST", server_request.request_method)
    assert_equal(["application/x-protobuf"], server_request.header["content-type"])
    assert_equal(TestData::ProtocolBuffers::METRICS, server_request.body)
  end

  def test_send_traces
    event = { "type" => "otlp_traces", "message" => TestData::JSON::TRACES }

    d = create_driver
    d.run(default_tag: "otlp.test") do
      d.feed(event)
    end

    assert_equal("/v1/traces", server_request.path)
    assert_equal("POST", server_request.request_method)
    assert_equal(["application/x-protobuf"], server_request.header["content-type"])
    assert_equal(TestData::ProtocolBuffers::TRACES, server_request.body)
  end

  def test_send_compressed_message
    event = { "type" => "otlp_logs", "message" => TestData::JSON::LOGS }

    d = create_driver(%[
      <http>
        endpoint "http://127.0.0.1:14318"
        compress gzip
      </http>
    ])
    d.run(default_tag: "otlp.test") do
      d.feed(event)
    end

    assert_equal("/v1/logs", server_request.path)
    assert_equal("POST", server_request.request_method)
    assert_equal(["application/x-protobuf"], server_request.header["content-type"])
    assert_equal(["gzip"], server_request.header["content-encoding"])
    assert_equal(TestData::ProtocolBuffers::LOGS, decompress(server_request.body).force_encoding(Encoding::ASCII_8BIT))
  end

  def test_unrecoverable_error
    server_response_code(500)
    event = { "type" => "otlp_logs", "message" => TestData::JSON::LOGS }

    d = create_driver
    d.run(default_tag: "otlp.test", shutdown: false) do
      d.feed(event)
    end

    assert_match(%r{got unrecoverable error response from 'http://127.0.0.1:14318/v1/logs', response code is 500},
                 d.instance.log.out.logs.join)

    d.instance_shutdown
  end

  def test_error_with_disabled_unrecoverable
    server_response_code(500)
    event = { "type" => "otlp_logs", "message" => TestData::JSON::LOGS }

    d = create_driver(%[
      <http>
        endpoint "http://127.0.0.1:14318"
        error_response_as_unrecoverable false
      </http>
    ])
    d.run(default_tag: "otlp.test", shutdown: false) do
      d.feed(event)
    end

    assert_match(%r{got error response from 'http://127.0.0.1:14318/v1/logs', response code is 500},
                 d.instance.log.out.logs.join)

    d.instance_shutdown
  end

  def test_write_with_retryable_response
    old_report_on_exception = Thread.report_on_exception
    Thread.report_on_exception = false # thread finished as invalid state since RetryableResponse raises.

    server_response_code(503)
    event = { "type" => "otlp_logs", "message" => TestData::JSON::LOGS }

    d = create_driver(%[
      <http>
        endpoint "http://127.0.0.1:14318"
        retryable_response_codes [503]
      </http>
    ])

    assert_raise(Fluent::Plugin::OtlpOutput::RetryableResponse) do
      d.run(default_tag: "otlp.test", shutdown: false) do
        d.feed(event)
      end
    end

    d.instance_shutdown
  ensure
    Thread.report_on_exception = old_report_on_exception
  end

  sub_test_case "HTTPS" do
    def server_config
      config = super
      config[:Port] = "14318"
      # WEBrick supports self-generated self-signed certificate
      config[:SSLEnable] = true
      config[:SSLCertName] = [["CN", WEBrick::Utils.getservername]]
      config
    end

    def config
      <<~"CONFIG"
        <http>
          endpoint "https://127.0.0.1:14318"
        </http>
        <transport tls>
          cert_path "#{File.expand_path(File.dirname(__FILE__) + '/../resources/certs/ca.crt')}"
          private_key_path "#{File.expand_path(File.dirname(__FILE__) + '/../resources/certs/ca.key')}"
          insecure true
        </transport>
      CONFIG
    end

    def test_https_send_logs
      event = { "type" => "otlp_logs", "message" => TestData::JSON::LOGS }

      d = create_driver
      d.run(default_tag: "otlp.test") do
        d.feed(event)
      end

      assert_equal("/v1/logs", server_request.path)
      assert_equal("POST", server_request.request_method)
      assert_equal(["application/x-protobuf"], server_request.header["content-type"])
      assert_equal(TestData::ProtocolBuffers::LOGS, server_request.body)
    end
  end

  def decompress(data)
    Zlib::GzipReader.new(StringIO.new(data)).read
  end
end
