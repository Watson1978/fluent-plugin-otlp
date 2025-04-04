# frozen_string_literal: true

require "fluent/plugin/otlp/constant"
require "google/protobuf"
require "opentelemetry/proto/collector/logs/v1/logs_service_pb"
require "opentelemetry/proto/collector/metrics/v1/metrics_service_pb"
require "opentelemetry/proto/collector/trace/v1/trace_service_pb"

module Fluent::Plugin::Otlp
  class Request
    class Logs
      def initialize(body)
        @request =
          if body.encoding == Encoding::BINARY
            Opentelemetry::Proto::Collector::Logs::V1::ExportLogsServiceRequest.decode(body)
          else
            Opentelemetry::Proto::Collector::Logs::V1::ExportLogsServiceRequest.decode_json(body)
          end
      end

      def encode
        Opentelemetry::Proto::Collector::Logs::V1::ExportLogsServiceRequest.encode(@request)
      end

      def record
        @request.to_json
      end
    end

    class Metrics
      def initialize(body)
        @request =
          if body.encoding == Encoding::BINARY
            Opentelemetry::Proto::Collector::Metrics::V1::ExportMetricsServiceRequest.decode(body)
          else
            Opentelemetry::Proto::Collector::Metrics::V1::ExportMetricsServiceRequest.decode_json(body)
          end
      end

      def encode
        Opentelemetry::Proto::Collector::Metrics::V1::ExportMetricsServiceRequest.encode(@request)
      end

      def record
        @request.to_json
      end
    end

    class Traces
      def initialize(body)
        @request =
          if body.encoding == Encoding::BINARY
            Opentelemetry::Proto::Collector::Trace::V1::ExportTraceServiceRequest.decode(body)
          else
            Opentelemetry::Proto::Collector::Trace::V1::ExportTraceServiceRequest.decode_json(body)
          end
      end

      def encode
        Opentelemetry::Proto::Collector::Trace::V1::ExportTraceServiceRequest.encode(@request)
      end

      def record
        @request.to_json
      end
    end
  end
end
