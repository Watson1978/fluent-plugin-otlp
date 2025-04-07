# frozen_string_literal: true

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

    config_section :buffer do
      config_set_default :chunk_keys, ["tag"]
      config_set_default :flush_at_shutdown, true
      config_set_default :chunk_limit_size, 10 * 1024
    end

    config_section :http, required: false, multi: false, init: true, param_name: :http_config do
      desc "The endpoint"
      config_param :endpoint, :string, default: "http://127.0.0.1:4318"
      desc 'The proxy for HTTP request'
      config_param :proxy, :string, default: ENV['HTTP_PROXY'] || ENV['http_proxy']
    end

    desc "Compress request body"
    config_param :compress, :enum, list: %i[text gzip], default: :text

    def initialize
      super

      @http_proxy_uri = nil
    end

    def configure(conf)
      super

      OtlpOutput.const_set(:HTTP_LOGS_ENDPOINT, "#{@http_config.endpoint}/v1/logs".freeze)
      OtlpOutput.const_set(:HTTP_METRICS_ENDPOINT, "#{@http_config.endpoint}/v1/metrics".freeze)
      OtlpOutput.const_set(:HTTP_TRACES_ENDPOINT, "#{@http_config.endpoint}/v1/traces".freeze)

      @http_proxy_uri = URI.parse(@http_config.proxy) if @http_config.proxy
    end

    def multi_workers_ready?
      true
    end

    def format(tag, time, record)
      JSON.generate(record)
    end

    def write(chunk)
      uri, req = create_uri_request(chunk)

      Net::HTTP.start(uri.host, uri.port, @http_proxy_uri&.host, @http_proxy_uri&.port, @http_proxy_uri&.user, @http_proxy_uri&.password) do |http|
        http.request(req)
      end
    end

    private

    def create_uri_request(chunk)
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
        raise "Unknown record type: #{record["type"]}"
      end

      uri = URI.parse(uri)
      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"] = Otlp::CONTENT_TYPE_PROTOBUF

      if @compress == :gzip
        req["Content-Encoding"] = Otlp::CONTENT_ENCODING_GZIP
        gz = Zlib::GzipWriter.new(StringIO.new)
        gz << body
        body = gz.close.string
      end

      req.body = body
      [uri, req]
    end
  end
end
