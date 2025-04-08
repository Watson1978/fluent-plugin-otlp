# frozen_string_literal: true

require "excon"
require "fluent/plugin/otlp/constant"
require "fluent/plugin/otlp/request"
require "fluent/plugin/output"
require "json"
require "net/http"
require "uri"
require "zlib"

module Fluent::Plugin
  class OtlpOutput < Output
    Fluent::Plugin.register_output("otlp", self)

    helpers :server

    config_section :buffer do
      config_set_default :chunk_keys, ["tag"]
      config_set_default :flush_at_shutdown, true
      config_set_default :chunk_limit_size, 10 * 1024
    end

    config_section :http, required: false, multi: false, init: true, param_name: :http_config do
      desc "The endpoint"
      config_param :endpoint, :string, default: "http://127.0.0.1:4318"
      desc "The proxy for HTTP request"
      config_param :proxy, :string, default: ENV["HTTP_PROXY"] || ENV["http_proxy"]
    end

    config_section :transport, required: false, multi: false, init: true, param_name: :transport_config do
      config_argument :protocol, :enum, list: [:tls], default: nil
    end

    desc "Compress request body"
    config_param :compress, :enum, list: %i[text gzip], default: :text

    def configure(conf)
      super

      OtlpOutput.const_set(:HTTP_LOGS_ENDPOINT, "#{@http_config.endpoint}/v1/logs".freeze)
      OtlpOutput.const_set(:HTTP_METRICS_ENDPOINT, "#{@http_config.endpoint}/v1/metrics".freeze)
      OtlpOutput.const_set(:HTTP_TRACES_ENDPOINT, "#{@http_config.endpoint}/v1/traces".freeze)

      @certs = {}
      if @transport_config.protocol == :tls
        @certs[:client_cert] = @transport_config.cert_path
        @certs[:client_key] = @transport_config.private_key_path
        @certs[:client_key_pass] = @transport_config.private_key_passphrase
        @certs[:ssl_verify_peer] = false if @transport_config.insecure
        @certs[:ssl_version] = @transport_config.version
      end
    end

    def multi_workers_ready?
      true
    end

    def format(tag, time, record)
      JSON.generate(record)
    end

    def write(chunk)
      uri, connection = create_connection(chunk)
      response = connection.post
      if response.status != 200
        log.error "got error response from '#{uri.to_s}'"
      end
    end

    private

    def create_connection(chunk)
      record = JSON.parse(chunk.read)
      msg = record["message"]

      case record["type"]
      when Otlp::RECORD_TYPE_LOGS
        uri = HTTP_LOGS_ENDPOINT
        body = Otlp::Request::Logs.new(msg).encode
      when Otlp::RECORD_TYPE_METRICS
        uri = HTTP_METRICS_ENDPOINT
        body = Otlp::Request::Metrics.new(msg).encode
      when Otlp::RECORD_TYPE_TRACES
        uri = HTTP_TRACES_ENDPOINT
        body = Otlp::Request::Traces.new(msg).encode
      else
        raise "Unknown record type: #{record['type']}"
      end

      headers = { "Content-Type" => Otlp::CONTENT_TYPE_PROTOBUF }
      if @compress == :gzip
        headers["Content-Encoding"] = Otlp::CONTENT_ENCODING_GZIP
        gz = Zlib::GzipWriter.new(StringIO.new)
        gz << body
        body = gz.close.string
      end

      connection = Excon.new(uri, body: body, headers: headers, proxy: @http_config.proxy, persistent: true, **@certs)
      [uri, connection]
    end
  end
end
