# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "tmpdir"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]

  # Disable displaying 'warning: literal string will be frozen in the future'
  ENV["RUBYOPT"] = "--disable=frozen_string_literal"
end

task default: :test

task :"regenerate:opentelemetry" do
  lib_path = File.expand_path("lib/opentelemetry")

  rm_rf lib_path
  cd Dir.tmpdir do
    sh "git clone https://github.com/open-telemetry/opentelemetry-proto.git --depth 1"
    cd "opentelemetry-proto" do
      files = Dir.glob("opentelemetry/**/*.proto")

      mkdir_p "gen"
      sh "grpc_tools_ruby_protoc --grpc_out=./gen --ruby_out=./gen --proto_path=. #{files.join(' ')}"
      mv "./gen/opentelemetry", lib_path
    end
  ensure
    rm_rf "opentelemetry-proto"
  end
end
