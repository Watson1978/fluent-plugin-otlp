# frozen_string_literal: true

require "test_helper"

class Fluent::Plugin::OtelTest < Test::Unit::TestCase
  test "VERSION" do
    assert do
      ::Fluent::Plugin::Otel.const_defined?(:VERSION)
    end
  end

  test "something useful" do
    assert_equal("expected", "actual")
  end
end
