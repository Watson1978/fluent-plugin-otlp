# frozen_string_literal: true

require "fluent/plugin"
require "openssl"

module Fluent::Plugin::Otlp
  CONTENT_TYPE = "Content-Type"
  CONTENT_TYPE_PAIN = "text/plain"
  CONTENT_TYPE_PROTOBUF = "application/x-protobuf"
  CONTENT_TYPE_JSON = "application/json"

  CONTENT_ENCODING = "Content-Encoding"
  CONTENT_ENCODING_GZIP = "gzip"

  RECORD_TYPE_LOGS = "otlp_logs"
  RECORD_TYPE_METRICS = "otlp_metrics"
  RECORD_TYPE_TRACES = "otlp_traces"

  TLS_VERSIONS_MAP =
    begin
      map = {
        TLSv1: OpenSSL::SSL::TLS1_VERSION,
        TLSv1_1: OpenSSL::SSL::TLS1_1_VERSION,
        TLSv1_2: OpenSSL::SSL::TLS1_2_VERSION
      }
      map[:TLSv1_3] = OpenSSL::SSL::TLS1_3_VERSION if defined?(OpenSSL::SSL::TLS1_3_VERSION)
      map.freeze
    end
end
