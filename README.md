# capistrano-autoscaling

A Capistrano recipe that configures [AutoScaling](http://aws.amazon.com/autoscaling/) on [Amazon Web Services](http://aws.amazon.com/) infrastructure for your application.

## Installation

Add this line to your application's Gemfile:

    gem 'capistrano-autoscaling'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capistrano-autoscaling

## Usage

This recipe will try to setup AutoScaling for your appliction.  The following actions are prepared to be invoked from Capistrano.

 * Create ELB for your application
 * Create AMI from EC2 instances behind your ELB
 * Create launch configurations from AMI of your application
 * Create auto scaling group for your application

To enable this recipe, add following in your `config/deploy.rb`.

    # in "config/deploy.rb"
    require "capistrano-autoscaling"
    set(:autoscaling_region, "ap-northeast-1")
    set(:autoscaling_access_key_id, "PUTYOURAWSACCESSKEYIDHERE")
    set(:autoscaling_secret_access_key, "PUTYOURAWSSECRETACCESSKEYHERE")
    set(:autoscaling_instance_type, "m1.small")
    set(:autoscaling_security_groups, %w(default))
    set(:autoscaling_min_size, 2)
    set(:autoscaling_max_size, 10)
    after "deploy:setup", "autoscaling:setup"
    after "deploy", "autoscaling:update"

TODO: Write usage instructions here


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Author

- YAMASHITA Yuu (https://github.com/yyuu)
- Geisha Tokyo Entertainment Inc. (http://www.geishatokyo.com/)

## License

MIT
