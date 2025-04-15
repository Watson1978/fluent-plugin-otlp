# Generated by the protocol buffer compiler.  DO NOT EDIT!
# Source: opentelemetry/proto/collector/metrics/v1/metrics_service.proto for package 'opentelemetry.proto.collector.metrics.v1'
# Original file comments:
# Copyright 2019, OpenTelemetry Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'grpc'
require 'opentelemetry/proto/collector/metrics/v1/metrics_service_pb'

module Opentelemetry
  module Proto
    module Collector
      module Metrics
        module V1
          module MetricsService
            # ServiceStub that can be used to push metrics between one Application
            # instrumented with OpenTelemetry and a collector, or between a collector and a
            # central collector.
            class Service

              include ::GRPC::GenericService

              self.marshal_class_method = :encode
              self.unmarshal_class_method = :decode
              self.service_name = 'opentelemetry.proto.collector.metrics.v1.MetricsService'

              rpc :Export, ::Opentelemetry::Proto::Collector::Metrics::V1::ExportMetricsServiceRequest, ::Opentelemetry::Proto::Collector::Metrics::V1::ExportMetricsServiceResponse
            end

            Stub = Service.rpc_stub_class
          end
        end
      end
    end
  end
end
