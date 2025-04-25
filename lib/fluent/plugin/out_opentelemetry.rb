# frozen_string_literal: true

require "fluent/plugin/opentelemetry/constant"
require "fluent/plugin/opentelemetry/request"
require "fluent/plugin/opentelemetry/service_stub"
require "fluent/plugin/output"

require "excon"
require "grpc"
require "json"
require "stringio"
require "zlib"

module Fluent::Plugin
  class OpentelemetryOutput < Output
    class RetryableResponse < StandardError; end

    Fluent::Plugin.register_output("opentelemetry", self)

    helpers :server

    config_section :buffer do
      config_set_default :chunk_keys, ["tag"]
    end

    config_section :http, required: false, multi: false, init: false, param_name: :http_config do
      desc "The endpoint"
      config_param :endpoint, :string, default: "http://127.0.0.1:4318"
      desc "The proxy for HTTP request"
      config_param :proxy, :string, default: ENV["HTTP_PROXY"] || ENV["http_proxy"]

      desc "Raise UnrecoverableError when the response is non success, 4xx/5xx"
      config_param :error_response_as_unrecoverable, :bool, default: true
      desc "The list of retryable response code"
      config_param :retryable_response_codes, :array, value_type: :integer, default: [429, 502, 503, 504]

      desc "Compress request body"
      config_param :compress, :enum, list: %i[text gzip], default: :text

      desc "The read timeout in seconds"
      config_param :read_timeout, :integer, default: 60
      desc "The write timeout in seconds"
      config_param :write_timeout, :integer, default: 60
      desc "The connect timeout in seconds"
      config_param :connect_timeout, :integer, default: 60
    end

    config_section :grpc, required: false, multi: false, init: false, param_name: :grpc_config do
      desc "The endpoint"
      config_param :endpoint, :string, default: "127.0.0.1:4317"
    end

    config_section :transport, required: false, multi: false, init: false, param_name: :transport_config do
      config_argument :protocol, :enum, list: [:tls], default: nil
    end

    def configure(conf)
      super

      unless [@http_config, @grpc_config].one?
        raise Fluent::ConfigError, "Please configure either <http> or <grpc> section."
      end

      @http_handler = HttpHandler.new(@http_config, @transport_config, log) if @http_config
      @grpc_handler = GrpcHandler.new(@grpc_config, @transport_config, log) if @grpc_config
    end

    def multi_workers_ready?
      true
    end

    def format(tag, time, record)
      JSON.generate(record)
    end

    def write(chunk)
      record = JSON.parse(chunk.read)

      if @grpc_handler
        @grpc_handler.export(record)
      else
        @http_handler.export(record)
      end
    end

    class HttpHandler
      def initialize(http_config, transport_config, logger)
        @http_config = http_config
        @transport_config = transport_config
        @logger = logger

        @tls_settings = {}
        if @transport_config.protocol == :tls
          @tls_settings[:client_cert] = @transport_config.cert_path
          @tls_settings[:client_key] = @transport_config.private_key_path
          @tls_settings[:client_key_pass] = @transport_config.private_key_passphrase
          @tls_settings[:ssl_min_version] = Opentelemetry::TLS_VERSIONS_MAP[@transport_config.min_version]
          @tls_settings[:ssl_max_version] = Opentelemetry::TLS_VERSIONS_MAP[@transport_config.max_version]
        end

        @timeout_settings = {
          read_timeout: http_config.read_timeout,
          write_timeout: http_config.write_timeout,
          connect_timeout: http_config.connect_timeout
        }
      end

      def export(record)
        uri, connection = create_http_connection(record)
        response = connection.post

        if response.status != 200
          if response.status == 400
            # The client MUST NOT retry the request when it receives HTTP 400 Bad Request response.
            raise Fluent::UnrecoverableError, "got unrecoverable error response from '#{uri}', response code is #{response.status}"
          end

          if @http_config.retryable_response_codes&.include?(response.status)
            raise RetryableResponse, "got retryable error response from '#{uri}', response code is #{response.status}"
          end
          if @http_config.error_response_as_unrecoverable
            raise Fluent::UnrecoverableError, "got unrecoverable error response from '#{uri}', response code is #{response.status}"
          else
            @logger.error "got error response from '#{uri}', response code is #{response.status}"
          end
        end
      end

      private

      def http_logs_endpoint
        "#{@http_config.endpoint}/v1/logs"
      end

      def http_metrics_endpoint
        "#{@http_config.endpoint}/v1/metrics"
      end

      def http_traces_endpoint
        "#{@http_config.endpoint}/v1/traces"
      end

      def create_http_connection(record)
        msg = record["message"]

        begin
          case record["type"]
          when Opentelemetry::RECORD_TYPE_LOGS
            uri = http_logs_endpoint
            body = Opentelemetry::Request::Logs.new(msg).body
          when Opentelemetry::RECORD_TYPE_METRICS
            uri = http_metrics_endpoint
            body = Opentelemetry::Request::Metrics.new(msg).body
          when Opentelemetry::RECORD_TYPE_TRACES
            uri = http_traces_endpoint
            body = Opentelemetry::Request::Traces.new(msg).body
          end
        rescue Google::Protobuf::ParseError => e
          # The message format does not comply with the OpenTelemetry protocol.
          raise ::Fluent::UnrecoverableError, e.message
        end

        headers = { Opentelemetry::CONTENT_TYPE => Opentelemetry::CONTENT_TYPE_PROTOBUF }
        if @http_config.compress == :gzip
          headers[Opentelemetry::CONTENT_ENCODING] = Opentelemetry::CONTENT_ENCODING_GZIP
          gz = Zlib::GzipWriter.new(StringIO.new)
          gz << body
          body = gz.close.string
        end

        Excon.defaults[:ssl_verify_peer] = false if @transport_config.insecure
        connection = Excon.new(uri, body: body, headers: headers, proxy: @http_config.proxy, persistent: true, **@tls_settings, **@timeout_settings)
        [uri, connection]
      end
    end

    class GrpcHandler
      def initialize(grpc_config, transport_config, logger)
        @grpc_config = grpc_config
        @transport_config = transport_config
        @logger = logger
      end

      def export(record)
        msg = record["message"]

        credential = :this_channel_is_insecure

        case record["type"]
        when Opentelemetry::RECORD_TYPE_LOGS
          service = Opentelemetry::ServiceStub::Logs.new(@grpc_config.endpoint, credential)
        when Opentelemetry::RECORD_TYPE_METRICS
          service = Opentelemetry::ServiceStub::Metrics.new(@grpc_config.endpoint, credential)
        when Opentelemetry::RECORD_TYPE_TRACES
          service = Opentelemetry::ServiceStub::Traces.new(@grpc_config.endpoint, credential)
        end

        begin
          service.export(msg)
        rescue Google::Protobuf::ParseError => e
          # The message format does not comply with the OpenTelemetry protocol.
          raise ::Fluent::UnrecoverableError, e.message
        end
      end
    end
  end
end
