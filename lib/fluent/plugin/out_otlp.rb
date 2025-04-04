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
    end

    desc "Compress request body"
    config_param :compress, :enum, list: %i[text gzip], default: :text

    def multi_workers_ready?
      true
    end

    def format(tag, time, record)
      JSON.generate(record)
    end

    def write(chunk)
      record = JSON.parse(chunk.read)
      msg = record["message"]

      case record["type"]
      when "otlp_logs"
        uri = "#{@http_config.endpoint}/v1/logs"
        body = Otlp::Request::Logs.new(msg).encode
      when "otlp_metrics"
        uri = "#{@http_config.endpoint}/v1/metrics"
        body = Otlp::Request::Metrics.new(msg).encode
      when "otlp_traces"
        uri = "#{@http_config.endpoint}/v1/traces"
        body = Otlp::Request::Traces.new(msg).encode
      end

      uri = URI.parse(uri)
      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"] = Otlp::CONTENT_TYPE_PROTOBUF

      if @compress == :gzip
        req["Content-Encoding"] = "gzip"
        gz = Zlib::GzipWriter.new(StringIO.new)
        gz << body
        body = gz.close.string
      end

      req.body = body

      Net::HTTP.start(uri.host, uri.port) do |http|
        http.request(req)
      end
    end
  end
end
