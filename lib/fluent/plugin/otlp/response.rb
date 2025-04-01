# frozen_string_literal: true

require 'fluent/plugin/otlp/constant'
require 'google/protobuf'
require 'opentelemetry/proto/collector/logs/v1/logs_service_pb.rb'
require 'opentelemetry/proto/collector/metrics/v1/metrics_service_pb'
require 'opentelemetry/proto/collector/trace/v1/trace_service_pb.rb'

module Fluent::Plugin::Otlp
  class Response
    def self.type(content_type)
      case content_type
      when CONTENT_TYPE_PROTOBUF
        :protobuf
      when CONTENT_TYPE_JSON
        :json
      else
        raise "unknown content-type: #{content_type}"
      end
    end

    class Logs
      def initialize(rejected: 0, error: '')
        @response = Opentelemetry::Proto::Collector::Logs::V1::ExportLogsServiceResponse.new(
          partial_success: Opentelemetry::Proto::Collector::Logs::V1::ExportLogsPartialSuccess.new(
            rejected_log_records: rejected,
            error_message: error
          )
        )
      end

      def body(type:)
        if type == :protobuf
          Opentelemetry::Proto::Collector::Logs::V1::ExportLogsServiceResponse.encode(@response)
        else
          @response.to_json
        end
      end
    end

    class Metrics
      def initialize(rejected: 0, error: '')
        @response = Opentelemetry::Proto::Collector::Metrics::V1::ExportMetricsServiceResponse.new(
          partial_success: Opentelemetry::Proto::Collector::Metrics::V1::ExportMetricsPartialSuccess.new(
            rejected_data_points: rejected,
            error_message: error
          )
        )
      end

      def body(type:)
        if type == :protobuf
          Opentelemetry::Proto::Collector::Metrics::V1::ExportMetricsServiceResponse.encode(@response)
        else
          @response.to_json
        end
      end
    end

    class Traces
      def initialize(rejected: 0, error: '')
        @response = Opentelemetry::Proto::Collector::Trace::V1::ExportTraceServiceResponse.new(
          partial_success: Opentelemetry::Proto::Collector::Trace::V1::ExportTracePartialSuccess.new(
            rejected_spans: rejected,
            error_message: error
          )
        )
      end

      def body(type:)
        if type == :protobuf
          Opentelemetry::Proto::Collector::Trace::V1::ExportTraceServiceResponse.encode(@response)
        else
          @response.to_json
        end
      end
    end
  end
end