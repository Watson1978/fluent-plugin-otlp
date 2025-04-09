# frozen_string_literal: true

require "helper"
require 'fluent/test/driver/input'
require 'fluent/plugin/in_otlp'

class Fluent::Plugin::OtelInputTest < Test::Unit::TestCase
  def config
    <<~CONFIG
      tag otlp.test
      <http>
        bind 127.0.0.1
        port 4318
      </http>
    CONFIG
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

end
