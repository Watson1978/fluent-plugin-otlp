# frozen_string_literal: true

require "fluent/plugin/otlp/constant"
require "opentelemetry/proto/collector/logs/v1/logs_service_pb"
require "opentelemetry/proto/collector/metrics/v1/metrics_service_pb"
require "opentelemetry/proto/collector/trace/v1/trace_service_pb"

require "google/protobuf"

module Fluent::Plugin::Otlp::Response
  def self.type(content_type)
    case content_type
    when Fluent::Plugin::Otlp::CONTENT_TYPE_PROTOBUF
      :protobuf
    when Fluent::Plugin::Otlp::CONTENT_TYPE_JSON
      :json
    else
      raise "unknown content-type: #{content_type}"
    end
  end

  class Logs
    def self.build(rejected: 0, error: "")
      Opentelemetry::Proto::Collector::Logs::V1::ExportLogsServiceResponse.new(
        partial_success: Opentelemetry::Proto::Collector::Logs::V1::ExportLogsPartialSuccess.new(
          rejected_log_records: rejected,
          error_message: error
        )
      )
    end

    def initialize(rejected: 0, error: "")
      @response = Logs.build(rejected: rejected, error: error)
    end

    def body(type:)
      if type == :protobuf
        @response.to_proto
      else
        @response.to_json
      end
    end
  end

  class Metrics
    def self.build(rejected: 0, error: "")
      Opentelemetry::Proto::Collector::Metrics::V1::ExportMetricsServiceResponse.new(
        partial_success: Opentelemetry::Proto::Collector::Metrics::V1::ExportMetricsPartialSuccess.new(
          rejected_data_points: rejected,
          error_message: error
        )
      )
    end

    def initialize(rejected: 0, error: "")
      @response = Metrics.build(rejected: rejected, error: error)
    end

    def body(type:)
      if type == :protobuf
        @response.to_proto
      else
        @response.to_json
      end
    end
  end

  class Traces
    def self.build(rejected: 0, error: "")
      Opentelemetry::Proto::Collector::Trace::V1::ExportTraceServiceResponse.new(
        partial_success: Opentelemetry::Proto::Collector::Trace::V1::ExportTracePartialSuccess.new(
          rejected_spans: rejected,
          error_message: error
        )
      )
    end

    def initialize(rejected: 0, error: "")
      @response = Traces.build(rejected: rejected, error: error)
    end

    def body(type:)
      if type == :protobuf
        @response.to_proto
      else
        @response.to_json
      end
    end
  end
end
