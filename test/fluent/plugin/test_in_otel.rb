# frozen_string_literal: true

require "helper"
require 'fluent/test/driver/input'
require 'fluent/plugin/in_otlp'
require 'excon'
require 'timecop'

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

  def teardown
    Timecop.return
  end

  def create_driver(conf=config)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::OtlpInput).configure(conf)
  end

  def test_configure
    d = create_driver
    assert_equal "otlp.test", d.instance.tag
    assert_equal "127.0.0.1", d.instance.http_config.bind
    assert_equal 4318, d.instance.http_config.port
  end

  def test_receive_json
    d = create_driver
    res = d.run(expect_records: 1) do
      post_json("/v1/metrics", Fluent::Plugin::Otlp::JSON::METRICS)
    end

    assert_equal(200, res.status)
    assert_equal("otlp.test", d.events[0][0])
    assert_equal({ type: "otlp_metrics", message: Fluent::Plugin::Otlp::JSON::METRICS }, d.events[0][2])
  end

  def post_json(path, json)
    headers = { "Content-Type" => "application/json" }
    post(path, headers, json)
  end

  def post(path, headers, body)
    connection = Excon.new("http://127.0.0.1:4318#{path}", body: body, headers: headers)
    connection.post
  end
end
