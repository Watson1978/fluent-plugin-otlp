# frozen_string_literal: true

require "fluent/plugin/input"
require "fluent/plugin/otlp/constant"
require "fluent/plugin/otlp/request"
require "fluent/plugin/otlp/response"
require "fluent/plugin/otlp/service_handler"
require "fluent/plugin_helper/http_server"
require "fluent/plugin_helper/thread"

require "zlib"

unless Fluent::PluginHelper::HttpServer::Request.method_defined?(:headers)
  # This API was introduced at fluentd v1.19.0.
  # Ref. https://github.com/fluent/fluentd/pull/4903
  # If we have supported v1.19.0+ only, we can remove this patch.
  module Fluent::PluginHelper::HttpServer
    module Extension
      refine Request do
        def headers
          @request.headers
        end
      end
    end
  end

  using Fluent::PluginHelper::HttpServer::Extension
end

module Fluent::Plugin
  class OtlpInput < Input
    Fluent::Plugin.register_input("otlp", self)

    helpers :thread, :http_server

    desc "The tag of the event."
    config_param :tag, :string

    config_section :http, required: false, multi: false, init: false, param_name: :http_config do
      desc "The address to bind to."
      config_param :bind, :string, default: "0.0.0.0"
      desc "The port to listen to."
      config_param :port, :integer, default: 4318
    end


    config_section :grpc, required: false, multi: false, init: false, param_name: :grpc_config do
      desc "The address to bind to."
      config_param :bind, :string, default: "0.0.0.0"
      desc "The port to listen to."
      config_param :port, :integer, default: 4317
    end

    config_section :transport, required: false, multi: false, init: true, param_name: :transport_config do
      config_argument :protocol, :enum, list: [:tls], default: nil
    end

    def configure(conf)
      super

      unless [@http_config, @grpc_config].any?
        raise Fluent::ConfigError, "Please configure either <http> or <grpc> section, or both."
      end
    end

    def start
      super

      if @http_config
        http_handler = HttpHandler.new
        http_server_create_http_server(:in_otlp_http_server, addr: @http_config.bind, port: @http_config.port, logger: log) do |serv|
          serv.post("/v1/logs") do |req|
            http_handler.logs(req) { |record| router.emit(@tag, Fluent::EventTime.now, { type: Otlp::RECORD_TYPE_LOGS, message: record }) }
          end
          serv.post("/v1/metrics") do |req|
            http_handler.metrics(req) { |record| router.emit(@tag, Fluent::EventTime.now, { type: Otlp::RECORD_TYPE_METRICS, message: record }) }
          end
          serv.post("/v1/traces") do |req|
            http_handler.traces(req) { |record| router.emit(@tag, Fluent::EventTime.now, { type: Otlp::RECORD_TYPE_TRACES, message: record }) }
          end
        end
      end

      if @grpc_config
        thread_create(:in_otlp_grpc_server) do
          grpc_handler = GrpcHandler.new(@grpc_config)
          grpc_handler.run(
            logs: lambda { |record|
              router.emit(@tag, Fluent::EventTime.now, { type: Otlp::RECORD_TYPE_LOGS, message: record })
            },
            metrics: lambda { |record|
              router.emit(@tag, Fluent::EventTime.now, { type: Otlp::RECORD_TYPE_METRICS, message: record })
            },
            traces: lambda { |record|
              router.emit(@tag, Fluent::EventTime.now, { type: Otlp::RECORD_TYPE_TRACES, message: record })
            }
          )
        end
      end
    end

    class HttpHandler
      def logs(req, &block)
        common(req, Otlp::Request::Logs, Otlp::Response::Logs, &block)
      end

      def metrics(req, &block)
        common(req, Otlp::Request::Metrics, Otlp::Response::Metrics, &block)
      end

      def traces(req, &block)
        common(req, Otlp::Request::Traces, Otlp::Response::Traces, &block)
      end

      private

      def common(req, request_class, response_class, &block)
        content_type = req.headers["content-type"]
        content_encoding = req.headers["content-encoding"]&.first
        return response_unsupported_media_type unless valid_content_type?(content_type)
        return response_bad_request(content_type) unless valid_content_encoding?(content_encoding)

        body = req.body
        body = Zlib::GzipReader.new(StringIO.new(body)).read if content_encoding == Otlp::CONTENT_ENCODING_GZIP

        begin
          record = request_class.new(body).record
        rescue Google::Protobuf::ParseError
          # The format in request body does not comply with the OpenTelemetry protocol.
          return response_bad_request(content_type)
        end

        block.call(record)

        res = response_class.new
        response(200, content_type, res.body(type: Otlp::Response.type(content_type)))
      end

      def valid_content_type?(content_type)
        case content_type
        when Otlp::CONTENT_TYPE_PROTOBUF, Otlp::CONTENT_TYPE_JSON
          true
        else
          false
        end
      end

      def valid_content_encoding?(content_encoding)
        return true if content_encoding.nil?

        content_encoding == Otlp::CONTENT_ENCODING_GZIP
      end

      def response(code, content_type, body)
        [code, { Otlp::CONTENT_TYPE => content_type }, body]
      end

      def response_unsupported_media_type
        response(415, Otlp::CONTENT_TYPE_PAIN, "415 unsupported media type, supported: [application/json, application/x-protobuf]")
      end

      def response_bad_request(content_type)
        response(400, content_type, "") # TODO: fix body message
      end
    end

    class GrpcHandler
      class ExceptionInterceptor < GRPC::ServerInterceptor
        def request_response(request:, call:, method:)
          # call actual service
          yield
        rescue StandardError => e
          puts "[#{method}] Error: #{e.message}"
          raise
        end
      end

      def initialize(grpc_config)
        @grpc_config = grpc_config
      end

      def run(logs:, metrics:, traces:)
        server = GRPC::RpcServer.new(interceptors: [ExceptionInterceptor.new])
        server.add_http2_port("#{@grpc_config.bind}:#{@grpc_config.port}", :this_port_is_insecure)

        logs_handler = Otlp::ServiceHandler::Logs.new
        logs_handler.callback = lambda { |request|
          logs.call(request.to_json)
          Otlp::Response::Logs.build
        }
        server.handle(logs_handler)

        metrics_handler = Otlp::ServiceHandler::Metrics.new
        metrics_handler.callback = lambda { |request|
          metrics.call(request.to_json)
          Otlp::Response::Metrics.build
        }
        server.handle(metrics_handler)

        traces_handler = Otlp::ServiceHandler::Traces.new
        traces_handler.callback = lambda { |request|
          traces.call(request.to_json)
          Otlp::Response::Traces.build
        }
        server.handle(traces_handler)

        server.run_till_terminated
      end
    end
  end
end
