# frozen_string_literal: true

module Fluent::Plugin::Otlp
  CONTENT_TYPE_PAIN = "text/plain"
  CONTENT_TYPE_PROTOBUF = "application/x-protobuf"
  CONTENT_TYPE_JSON = "application/json"

  CONTENT_ENCODING_GZIP = "gzip"

  RECORD_TYPE_LOGS = "otlp_logs"
  RECORD_TYPE_METRICS = "otlp_metrics"
  RECORD_TYPE_TRACES = "otlp_traces"
end
