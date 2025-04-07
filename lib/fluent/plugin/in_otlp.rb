# frozen_string_literal: true

require "fluent/plugin/input"
require "fluent/plugin/otlp/constant"
require "fluent/plugin/otlp/request"
require "fluent/plugin/otlp/response"
require "zlib"

module Fluent::Plugin
  class OtlpInput < Input
    Fluent::Plugin.register_input("otlp", self)

    helpers :http_server

    desc "The tag of the event."
    config_param :tag, :string

    config_section :http, required: false, multi: false, init: true, param_name: :http_config do
      desc "The address to bind to."
      config_param :bind, :string, default: "0.0.0.0"
      desc "The port to listen to."
      config_param :port, :integer, default: 4318
    end

    config_section :transport, required: false, multi: false, init: true, param_name: :transport_config do
      config_argument :protocol, :enum, list: [:tls], default: nil
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
        [code, { "Content-Type" => content_type }, body]
      end

      def response_unsupported_media_type
        response(415, Otlp::CONTENT_TYPE_PAIN, "415 unsupported media type, supported: [application/json, application/x-protobuf]")
      end

      def response_bad_request(content_type)
        response(400, content_type, "") # TODO: fix body message
      end
    end

    def start
      super

      handler = HttpHandler.new
      http_server_create_http_server(:in_otel_http_server_helper, addr: @http_config.bind, port: @http_config.port, logger: log) do |serv|
        serv.post("/v1/logs") do |req|
          handler.logs(req) { |record| router.emit(@tag, Fluent::EventTime.now, { type: Otlp::RECORD_TYPE_LOGS, message: record }) }
        end
        serv.post("/v1/metrics") do |req|
          handler.metrics(req) { |record| router.emit(@tag, Fluent::EventTime.now, { type: Otlp::RECORD_TYPE_METRICS, message: record }) }
        end
        serv.post("/v1/traces") do |req|
          handler.traces(req) { |record| router.emit(@tag, Fluent::EventTime.now, { type: Otlp::RECORD_TYPE_TRACES, message: record }) }
        end
      end
    end
  end
end
