# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "fluent-plugin-otlp"
  spec.version = "0.1.0"
  spec.authors = ["Watson"]
  spec.email = ["watson1978@gmail.com"]

  spec.summary = "Write a short summary, because RubyGems requires one."
  spec.description = "Write a longer description or delete this line."
  spec.homepage = "https://github.com/watson1978/fluent-plugin-otlp"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/watson1978/fluent-plugin-otlp"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[test/ .git .github Gemfile])
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency("async-http", "~> 0.88.0")
  spec.add_dependency("fluentd", "~> 1.18")
  spec.add_dependency("google-protobuf", "~> 4.30")
end
