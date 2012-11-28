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
    after "deploy:cold", "autoscaling:update"
    after "deploy:rollback", "autoscaling:update"
    after "autoscaling:update", "autoscaling:cleanup"

The following options are preserved to manage AutoScaling.

### General options:

 * `:autoscaling_region` - The region name of AWS.
 * `:autoscaling_access_key_id` - The access key of AWS. By default, find one from `:aws_access_key_id` and `ENV["AWS_ACCESS_KEY_ID"]`.
 * `:autoscaling_secret_access_key` - The secret access key of AWS. By default, find one from `:aws_secret_access_key` and `ENV["AWS_SECRET_ACCESS_KEY"]`.
 * `:autoscaling_log_level` - The log level for AWS SDK.
 * `:autoscaling_application` - The basename for AutoScaling configurations. By default, generate from `:application`.
 * `:autoscaling_availability_zones` - The availability zones which will be used with AutoScaling. By default, use all availability zones within specified region.
 * `:autoscaling_instance_type` - The instance type which will be used with AutoScaling. By default, use `t1.micro`.
 * `:autoscaling_security_groups` - The security groups which will be used with AutoScaling. By default, use `%w(default)`.
 * `:autoscaling_min_size` - The minimal size of AutoScaling cluster. By default, use `1`.
 * `:autoscaling_max_size` - The maximum size of AutoScaling cluster. By default, use `:autoscaling_min_size`.

### ELB options

 * `:autoscaling_create_elb` - Controls whether create new ELB or not. By defalut, `true`.
 * `:autoscaling_elb_instance` - The ELB instance. By default, create new ELB instance if `:autoscaling_create_elb` is true.
 * `:autoscaling_elb_listeners` - A Hash of the listener configuration for ELB. By default, generate from `:autoscaling_elb_port` and `:autoscaling_elb_protocol`.
 * `:autoscaling_elb_port` - The ELB port. By default, use `80`.
 * `:autoscaling_elb_protocol` - The ELB protocol. By default, use `:http`.
 * `:autoscaling_elb_instance_port` - The instance port behind ELB. By default, use `:autoscaling_elb_port`.
 * `:autoscaling_elb_instance_protocol` - The instance protocol behind ELB. By default, use `:autoscaling_elb_protocol`.
 * `:autoscaling_elb_healthy_threshold` - The healthy threshold of ELB. By default, use `10`.
 * `:autoscaling_elb_unhealthy_threshold` - The unhealthy threshold of ELB. By default, use `2`.
 * `:autoscaling_elb_health_check_interval` - The health check interval of ELB. By default, use `30`.
 * `:autoscaling_elb_health_check_timeout` - The health check timeout of ELB. By default, use `5`.
 * `:autoscaling_elb_health_check_target` - The health check target of ELB. By default, generate from first listener in `:autoscaling_elb_listeners`.
 * `:autoscaling_elb_health_check_target_path` - The health check target path for HTTP services. By default, use `"/"`.

### EC2 options

 * `:autoscaling_ec2_instances` - The EC2 instances behind ELB.
 * `:autoscaling_ec2_instance_dns_names` - The DNS name of EC2 instances behind ELB.
 * `:autoscaling_ec2_instance_private_dns_names` - The private DNS name of EC2 instances behind ELB.

### AMI options

 * `:autoscaling_create_image` - Controls whether create new AMI or not. By default, `true`.
 * `:autoscaling_image` - The AMI of application. By default, create new AMI if `:autoscaling_create_image` is true.
 * `:autoscaling_image_extra_options` - The extra options for creating new AMIs.
 * `:autoscaling_keep_images` - How many AMIs do you want to keep on `autoscaling:cleanup` task. By default, keep 2 AMIs.

### LaunchConfiguration options

 * `:autoscaling_create_launch_configuration` - Controls whether create new launch configuration or not.
 * `:autoscaling_launch_configuration` - The launch configuration of application. By default, create new launch configuration if `:autoscaling_create_launch_configuration` is true.
 * `:autoscaling_launch_configuration_extra_options` - The extra options for creating new launch configurations.

### AutoScalingGroup options

 * `:autoscaling_create_group` - Controls whether create new group or not. By default, `true`.
 * `:autoscaling_group` - The group for application. By default, create new group if `:autoscaling_create_group` is true.
 * `:autoscaling_group_extra_options` - The extra options for creating new group.

### ScalingPolicy options

 * `:autoscaling_create_policy` - Controls whether create new policies or not.
 * `:autoscaling_expand_policy` - The scale-out policy.
 * `:autoscaling_shrink_policy` - The scale-in policy.
 * `:autoscaling_expand_policy_adjustment` - The scale-out adjustment. By defualt, use `1`.
 * `:autoscaling_shrink_policy_adjustment` - The scale-in adjustment. By default, use `-1`.

### MetricAlarm options

 * `:autoscaling_create_alarm` - Controls whether create new alarms or not.
 * `:autoscaling_expand_alarm_definitions` - The definition of scale-out alarms.
 * `:autoscaling_shrink_alarm_definitions` - The definition of scale-in alarms.


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
