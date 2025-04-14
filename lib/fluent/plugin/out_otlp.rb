# frozen_string_literal: true

require "fluent/plugin/otlp/constant"
require "fluent/plugin/otlp/request"
require "fluent/plugin/otlp/service"
require "fluent/plugin/output"

require "excon"
require "grpc"
require "json"
require "stringio"
require "zlib"

module Fluent::Plugin
  class OtlpOutput < Output
    class RetryableResponse < StandardError; end

    Fluent::Plugin.register_output("otlp", self)

    helpers :server

    config_section :buffer do
      config_set_default :chunk_keys, ["tag"]
      config_set_default :flush_at_shutdown, true
      config_set_default :chunk_limit_size, 10 * 1024
    end

    config_section :http, required: false, multi: false, init: false, param_name: :http_config do
      desc "The endpoint"
      config_param :endpoint, :string, default: "http://127.0.0.1:4318"
      desc "The proxy for HTTP request"
      config_param :proxy, :string, default: ENV["HTTP_PROXY"] || ENV["http_proxy"]

      desc "Raise UnrecoverableError when the response is non success, 4xx/5xx"
      config_param :error_response_as_unrecoverable, :bool, default: true
      desc "The list of retryable response code"
      config_param :retryable_response_codes, :array, value_type: :integer, default: nil

      desc "Compress request body"
      config_param :compress, :enum, list: %i[text gzip], default: :text
    end

    config_section :grpc, required: false, multi: false, init: false, param_name: :grpc_config do
      desc "The endpoint"
      config_param :endpoint, :string, default: "127.0.0.1:4317"
    end

    config_section :transport, required: false, multi: false, init: true, param_name: :transport_config do
      config_argument :protocol, :enum, list: [:tls], default: nil
    end

    def configure(conf)
      super

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
      if @http_handler
        @http_handler.export(chunk)

        return
      end

      if @grpc_handler
        @grpc_handler.export(chunk)
      end
    end

    private

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
          @tls_settings[:ssl_min_version] = Otlp::TLS_VERSIONS_MAP[@transport_config.min_version]
          @tls_settings[:ssl_max_version] = Otlp::TLS_VERSIONS_MAP[@transport_config.max_version]
        end
      end

      def export(chunk)
        uri, connection = create_http_connection(chunk)
        response = connection.post

        if response.status != 200
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

      def create_http_connection(chunk)
        record = JSON.parse(chunk.read)
        msg = record["message"]

        begin
          case record["type"]
          when Otlp::RECORD_TYPE_LOGS
            uri = http_logs_endpoint
            body = Otlp::Request::Logs.new(msg).encode
          when Otlp::RECORD_TYPE_METRICS
            uri = http_metrics_endpoint
            body = Otlp::Request::Metrics.new(msg).encode
          when Otlp::RECORD_TYPE_TRACES
            uri = http_traces_endpoint
            body = Otlp::Request::Traces.new(msg).encode
          end
        rescue Google::Protobuf::ParseError => e
          # The message format does not comply with the OpenTelemetry protocol.
          raise ::Fluent::UnrecoverableError, e.message
        end

        headers = { Otlp::CONTENT_TYPE => Otlp::CONTENT_TYPE_PROTOBUF }
        if @http_config.compress == :gzip
          headers[Otlp::CONTENT_ENCODING] = Otlp::CONTENT_ENCODING_GZIP
          gz = Zlib::GzipWriter.new(StringIO.new)
          gz << body
          body = gz.close.string
        end

        Excon.defaults[:ssl_verify_peer] = false if @transport_config.insecure
        connection = Excon.new(uri, body: body, headers: headers, proxy: @http_config.proxy, persistent: true, **@tls_settings)
        [uri, connection]
      end
    end

    class GrpcHandler
      def initialize(grpc_config, transport_config, logger)
        @grpc_config = grpc_config
        @transport_config = transport_config
        @logger = logger
      end

      def export(chunk)
        record = JSON.parse(chunk.read)
        msg = record["message"]

        credential = :this_channel_is_insecure

        case record["type"]
        when Otlp::RECORD_TYPE_LOGS
          service = Otlp::Service::Logs.new(@grpc_config.endpoint, credential)
        when Otlp::RECORD_TYPE_METRICS
          service = Otlp::Service::Metrics.new(@grpc_config.endpoint, credential)
        when Otlp::RECORD_TYPE_TRACES
          service = Otlp::Service::Traces.new(@grpc_config.endpoint, credential)
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
