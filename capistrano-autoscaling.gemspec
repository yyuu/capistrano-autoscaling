# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'capistrano-autoscaling/version'

Gem::Specification.new do |gem|
  gem.name          = "capistrano-autoscaling"
  gem.version       = Capistrano::AutoScaling::VERSION
  gem.authors       = ["Yamashita Yuu"]
  gem.email         = ["yamashita@geishatokyo.com"]
  gem.description   = %q{A Capistrano recipe that configures AutoScaling on Amazon Web Services infrastructure for your application.}
  gem.summary       = %q{A Capistrano recipe that configures AutoScaling on Amazon Web Services infrastructure for your application.}
  gem.homepage      = "https://github.com/yyuu/capistrano-autoscaling"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency("capistrano", "< 3")
  gem.add_dependency("aws-sdk", ">= 1.5.4")
end
