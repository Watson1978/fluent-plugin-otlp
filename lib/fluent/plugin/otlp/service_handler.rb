# frozen_string_literal: true

require "fluent/plugin/otlp/response"

require "opentelemetry/proto/collector/logs/v1/logs_service_services_pb"
require "opentelemetry/proto/collector/metrics/v1/metrics_service_services_pb"
require "opentelemetry/proto/collector/trace/v1/trace_service_services_pb"

require "grpc"

class Fluent::Plugin::Otlp::ServiceHandler
  class Logs < Opentelemetry::Proto::Collector::Logs::V1::LogsService::Service
    def callback=(block)
      @callback = block
    end

    def export(req)
      @callback.call(req)
    end
  end

  class Metrics < Opentelemetry::Proto::Collector::Metrics::V1::MetricsService::Service
    def callback=(block)
      @callback = block
    end

    def export(req, _call)
      @callback.call(req)
    end
  end

  class Traces < Opentelemetry::Proto::Collector::Trace::V1::TraceService::Service
    def callback=(block)
      @callback = block
    end

    def export(req)
      @callback.call(req)
    end
  end
end
