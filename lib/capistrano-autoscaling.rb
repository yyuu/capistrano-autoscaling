require "aws"
require "capistrano-autoscaling/version"
require "yaml"

module Capistrano
  module AutoScaling
    def self.extended(configuration)
      configuration.load {
        namespace(:autoscaling) {
## AWS
          _cset(:autoscaling_region, "us-east-1")
          _cset(:autoscaling_access_key_id) {
            fetch(:aws_access_key_id, ENV["AWS_ACCESS_KEY_ID"]) or abort("AWS_ACCESS_KEY_ID is not set")
          }
          _cset(:autoscaling_secret_access_key) {
            fetch(:aws_secret_access_key, ENV["AWS_SECRET_ACCESS_KEY"]) or abort("AWS_SECRET_ACCESS_KEY is not set")
          }
          _cset(:autoscaling_aws_options) {
            options = {
              :access_key_id => autoscaling_access_key_id,
              :secret_access_key => autoscaling_secret_access_key,
              :log_level => fetch(:autoscaling_log_level, :debug),
              :region => autoscaling_region,
            }.merge(fetch(:autoscaling_aws_extra_options, {}))
          }
          _cset(:autoscaling_aws) { AWS.tap { |aws| aws.config(autoscaling_aws_options) } }
          _cset(:autoscaling_autoscaling_client) { autoscaling_aws.auto_scaling(fetch(:autoscaling_autoscaling_aws_options, {})) }
          _cset(:autoscaling_cloudwatch_client) { autoscaling_aws.cloud_watch(fetch(:autoscaling_cloudwatch_options,{})) }
          _cset(:autoscaling_ec2_client) { autoscaling_aws.ec2(fetch(:autoscaling_ec2_options, {})) }
          _cset(:autoscaling_elb_client) { autoscaling_aws.elb(fetch(:autoscaling_elb_options, {})) }

          def autoscaling_name_mangling(s)
            s.to_s.gsub(/[^0-9A-Za-z]/, "-")
          end

## general
          _cset(:autoscaling_application) { autoscaling_name_mangling(application) }
          _cset(:autoscaling_timestamp) { Time.now.strftime("%Y%m%d%H%M%S") }
          _cset(:autoscaling_availability_zones) { autoscaling_ec2_client.availability_zones.to_a.map { |az| az.name } }
          _cset(:autoscaling_subnets, nil) # VPC only
          _cset(:autoscaling_wait_interval, 1.0)
          _cset(:autoscaling_keep_images, 2)
          _cset(:autoscaling_instance_type, "t1.micro")
          _cset(:autoscaling_security_groups, %w(default))
          _cset(:autoscaling_min_size, 1)
          _cset(:autoscaling_max_size) { autoscaling_min_size }

## behaviour
          _cset(:autoscaling_create_elb, true)
          _cset(:autoscaling_create_image, true)
          _cset(:autoscaling_create_launch_configuration) {
            autoscaling_create_image or ( autoscaling_image and autoscaling_image.exists? )
          }
          _cset(:autoscaling_create_group) {
            ( autoscaling_create_elb or ( autoscaling_elb_instance and autoscaling_elb_instance.exists? ) ) and
              autoscaling_create_launch_configuration
          }
          _cset(:autoscaling_create_policy) { autoscaling_create_group }
          _cset(:autoscaling_create_alarm) { autoscaling_create_policy }

## ELB
          _cset(:autoscaling_elb_instance_name_prefix, "")
          _cset(:autoscaling_elb_instance_name) { "#{autoscaling_elb_instance_name_prefix}#{autoscaling_application}" }
          _cset(:autoscaling_elb_instance) { autoscaling_elb_client.load_balancers[autoscaling_elb_instance_name] rescue nil }
          _cset(:autoscaling_elb_port, 80)
          _cset(:autoscaling_elb_protocol, :http)
          _cset(:autoscaling_elb_listeners) {
            [
              {
                :port => autoscaling_elb_port,
                :protocol => autoscaling_elb_protocol,
                :instance_port => fetch(:autoscaling_elb_instance_port, autoscaling_elb_port),
                :instance_protocol => fetch(:autoscaling_elb_instance_protocol, autoscaling_elb_protocol),
              },
            ]
          }
          _cset(:autoscaling_elb_availability_zones) { autoscaling_availability_zones }
          _cset(:autoscaling_elb_subnets) { autoscaling_subnets } # VPC only
          _cset(:autoscaling_elb_security_groups) { autoscaling_security_groups } # VPC only
          _cset(:autoscaling_elb_scheme, "internal") # VPC only
          _cset(:autoscaling_elb_instance_options) {
            options = {
              :listeners => autoscaling_elb_listeners,
            }
            if autoscaling_elb_subnets and not autoscaling_elb_subnets.empty?
              # VPC
              options[:subnets] = autoscaling_elb_subnets
              options[:security_groups] = autoscaling_elb_security_groups
              options[:scheme] = autoscaling_elb_scheme
            else
              # non-VPC
              options[:availability_zones] = autoscaling_elb_availability_zones
            end
            options.merge(fetch(:autoscaling_elb_instance_extra_options, {}))
          }
          _cset(:autoscaling_elb_health_check_target_path, "/")
          _cset(:autoscaling_elb_health_check_target) {
            autoscaling_elb_listeners.map { |listener|
              if /^https?$/i =~ listener[:instance_protocol]
                "#{listener[:instance_protocol].to_s.upcase}:#{listener[:instance_port]}#{autoscaling_elb_health_check_target_path}"
              else
                "#{listener[:instance_protocol].to_s.upcase}:#{listener[:instance_port]}"
              end
            }.first
          }
          _cset(:autoscaling_elb_health_check_options) {
            {
              :healthy_threshold => fetch(:autoscaling_elb_healthy_threshold, 10).to_i,
              :unhealthy_threshold => fetch(:autoscaling_elb_unhealthy_threshold, 2).to_i,
              :interval => fetch(:autoscaling_elb_health_check_interval, 30).to_i,
              :timeout => fetch(:autoscaling_elb_health_check_timeout, 5).to_i,
              :target => autoscaling_elb_health_check_target,
            }.merge(fetch(:autoscaling_elb_health_check_extra_options, {}))
          }

## EC2
          _cset(:autoscaling_ec2_instance_name) { autoscaling_application }
          _cset(:autoscaling_ec2_instances) {
            if autoscaling_elb_instance and autoscaling_elb_instance.exists?
              autoscaling_elb_instance.instances.to_a
            else
              abort("ELB is not ready: #{autoscaling_elb_instance_name}")
            end
          }
          _cset(:autoscaling_ec2_instance_dns_names) { autoscaling_ec2_instances.map { |instance| instance.dns_name } }
          _cset(:autoscaling_ec2_instance_private_dns_names) { autoscaling_ec2_instances.map { |instance| instance.private_dns_name } }
          _cset(:autoscaling_ec2_instance_public_dns_names) { autoscaling_ec2_instances.map { |instance| instance.public_dns_name } }
          _cset(:autoscaling_ec2_instance_ip_addresses) { autoscaling_ec2_instances.map { |instance| instance.ip_address } }
          _cset(:autoscaling_ec2_instance_private_ip_addresses) { autoscaling_ec2_instances.map { |instance| instance.private_ip_address } }
          _cset(:autoscaling_ec2_instance_public_ip_addresses) { autoscaling_ec2_instances.map { |instance| instance.public_ip_address } }

## AMI
          _cset(:autoscaling_image_name_prefix) { "#{autoscaling_application}/" }
          _cset(:autoscaling_image_name) { "#{autoscaling_image_name_prefix}#{autoscaling_timestamp}" }
          _cset(:autoscaling_image_instance) {
            if 0 < autoscaling_ec2_instances.length
              autoscaling_ec2_instances.reject { |instance| instance.root_device_type != :ebs }.last
            else
              abort("No EC2 instances are ready to create AMI.")
            end
          }
          _cset(:autoscaling_image_options) {
            { :no_reboot => true }.merge(fetch(:autoscaling_image_extra_options, {}))
          }
          _cset(:autoscaling_image_tag_name) { autoscaling_application }
          _cset(:autoscaling_image) {
            autoscaling_ec2_client.images.with_owner("self").filter("name", autoscaling_image_name).to_a.first
          }
          _cset(:autoscaling_images) {
            autoscaling_ec2_client.images.with_owner("self").filter("name", "#{autoscaling_image_name_prefix}*").to_a
          }

## LaunchConfiguration
          _cset(:autoscaling_launch_configuration) {
            autoscaling_autoscaling_client.launch_configurations[autoscaling_launch_configuration_name] rescue nil
          }
          _cset(:autoscaling_launch_configuration_name_prefix, "")
          _cset(:autoscaling_launch_configuration_name) { "#{autoscaling_launch_configuration_name_prefix}#{autoscaling_image_name}" }
          _cset(:autoscaling_launch_configuration_instance_type) { autoscaling_instance_type }
          _cset(:autoscaling_launch_configuration_security_groups) { autoscaling_security_groups }
          _cset(:autoscaling_launch_configuration_options) {
            {
              :security_groups => autoscaling_launch_configuration_security_groups,
            }.merge(fetch(:autoscaling_launch_configuration_extra_options, {}))
          }

## AutoScalingGroup
          _cset(:autoscaling_group_name_prefix, "")
          _cset(:autoscaling_group_name) { "#{autoscaling_group_name_prefix}#{autoscaling_application}" }
          _cset(:autoscaling_group_availability_zones) { autoscaling_availability_zones }
          _cset(:autoscaling_group_subnets) { autoscaling_subnets } # VPC only
          _cset(:autoscaling_group_options) {
            options = {
              :min_size => fetch(:autoscaling_group_min_size, autoscaling_min_size),
              :max_size => fetch(:autoscaling_group_max_size, autoscaling_max_size),
            }
            if autoscaling_group_subnets and not autoscaling_group_subnets.empty?
              # VPC
              options[:subnets] = autoscaling_group_subnets
            else
              # non-VPC
              options[:availability_zones] = autoscaling_group_availability_zones
            end
            options.merge(fetch(:autoscaling_group_extra_options, {}))
          }
          _cset(:autoscaling_group) { autoscaling_autoscaling_client.groups[autoscaling_group_name] rescue nil }

## ScalingPolicy
          _cset(:autoscaling_expand_policy_name_prefix, "expand-")
          _cset(:autoscaling_shrink_policy_name_prefix, "shrink-")
          _cset(:autoscaling_expand_policy_name) { "#{autoscaling_expand_policy_name_prefix}#{autoscaling_application}" }
          _cset(:autoscaling_shrink_policy_name) { "#{autoscaling_shrink_policy_name_prefix}#{autoscaling_application}" }
          _cset(:autoscaling_expand_policy_options) {
            {
              :scaling_adjustment => fetch(:autoscaling_expand_policy_adjustment, 1),
              :cooldown => fetch(:autoscaling_expand_policy_cooldown, 300),
              :adjustment_type => fetch(:autoscaling_expand_policy_type, "ChangeInCapacity"),
            }.merge(fetch(:autoscaling_expand_policy_extra_options, {}))
          }
          _cset(:autoscaling_shrink_policy_options) {
            {
              :scaling_adjustment => fetch(:autoscaling_shrink_policy_adjustment, -1),
              :cooldown => fetch(:autoscaling_shrink_policy_cooldown, 300),
              :adjustment_type => fetch(:autoscaling_shrink_policy_type, "ChangeInCapacity"),
            }.merge(fetch(:autoscaling_shrink_policy_extra_options, {}))
          }
          _cset(:autoscaling_expand_policy) { autoscaling_group.scaling_policies[autoscaling_expand_policy_name] rescue nil }
          _cset(:autoscaling_shrink_policy) { autoscaling_group.scaling_policies[autoscaling_shrink_policy_name] rescue nil }

## Alarm
          _cset(:autoscaling_expand_alarm_options) {
            {
              :period => fetch(:autoscaling_expand_alarm_period, 60),
              :evaluation_periods => fetch(:autoscaling_expand_alarm_evaluation_periods, 1),
            }.merge(fetch(:autoscaling_expand_alarm_extra_options, {}))
          }
          _cset(:autoscaling_shrink_alarm_options) {
            {
              :period => fetch(:autoscaling_shrink_alarm_period, 60),
              :evaluation_periods => fetch(:autoscaling_shrink_alarm_evaluation_periods, 1),
            }.merge(fetch(:autoscaling_shrink_alarm_extra_options, {}))
          }
          _cset(:autoscaling_expand_alarm_name_prefix, "alarm-expand-")
          _cset(:autoscaling_shrink_alarm_name_prefix, "alarm-shrink-")
          _cset(:autoscaling_expand_alarm_name) { "#{autoscaling_expand_alarm_name_prefix}#{autoscaling_application}" }
          _cset(:autoscaling_shrink_alarm_name) { "#{autoscaling_shrink_alarm_name_prefix}#{autoscaling_application}" }
          _cset(:autoscaling_expand_alarm_definitions) {{
            autoscaling_expand_alarm_name => {
              :statistic => fetch(:autoscaling_expand_alarm_evaluation_statistic, "Average"),
              :namespace => fetch(:autoscaling_expand_alarm_namespace, "AWS/EC2"),
              :metric_name => fetch(:autoscaling_expand_alarm_metric_name, "CPUUtilization"),
              :comparison_operator => fetch(:autoscaling_expand_alarm_comparison_operator, "GreaterThanThreshold"),
              :threshold => fetch(:autoscaling_expand_alarm_threshold, 60),
            },
          }}
          _cset(:autoscaling_shrink_alarm_definitions) {{
            autoscaling_shrink_alarm_name => {
              :statistic => fetch(:autoscaling_shrink_alarm_evaluation_statistic, "Average"),
              :namespace => fetch(:autoscaling_shrink_alarm_namespace, "AWS/EC2"),
              :metric_name => fetch(:autoscaling_shrink_alarm_metric_name, "CPUUtilization"),
              :comparison_operator => fetch(:autoscaling_shrink_alarm_comparison_operator, "LessThanThreshold"),
              :threshold => fetch(:autoscaling_shrink_alarm_threshold, 30),
            },
          }}

          desc("Setup AutoScaling.")
          task(:setup, :roles => :app, :except => { :no_release => true }) {
            update_elb
          }
          _cset(:autoscaling_setup_after_hooks, ["deploy:setup"])
          on(:load) {
            [ autoscaling_setup_after_hooks ].flatten.each do |t|
              after t, "autoscaling:setup" if t
            end
          }

          desc("Remove AutoScaling settings.")
          task(:destroy, :roles => :app, :except => { :no_release => true }) {
            destroy_alarm
            destroy_policy
            destroy_group
            destroy_elb
          }

          desc("Register current instance for AutoScaling.")
          task(:update, :roles => :app, :except => { :no_release => true }) {
            suspend
            update_image
            update_launch_configuration
            update_group
            update_policy
            update_alarm
            resume
          }
          _cset(:autoscaling_update_after_hooks, ["deploy", "deploy:cold", "deploy:rollback"])
          on(:load) {
            [ autoscaling_update_after_hooks ].flatten.each do |t|
              after t, "autoscaling:update" if t
            end
          }

          task(:update_elb, :roles => :app, :except => { :no_release => true }) {
            if autoscaling_create_elb
              if autoscaling_elb_instance and autoscaling_elb_instance.exists?
                logger.debug("Found ELB: #{autoscaling_elb_instance.name}")
                if autoscaling_elb_instance_options.has_key?(:availability_zones)
                  autoscaling_elb_instance.availability_zones.enable(*autoscaling_elb_instance_options[:availability_zones])
                end
                autoscaling_elb_listeners.each do |listener|
                  autoscaling_elb_instance.listeners.create(listener)
                end
              else
                logger.debug("Creating ELB instance: #{autoscaling_elb_instance_name}")
                set(:autoscaling_elb_instance, autoscaling_elb_client.load_balancers.create(
                  autoscaling_elb_instance_name, autoscaling_elb_instance_options))
                sleep(autoscaling_wait_interval) unless autoscaling_elb_instance.exists?
                logger.debug("Created ELB instance: #{autoscaling_elb_instance.name}")
                logger.info("You must setup EC2 instance(s) behind the ELB manually: #{autoscaling_elb_instance_name}")
              end
              logger.debug("Configuring ELB health check: #{autoscaling_elb_instance_name}")
              autoscaling_elb_instance.configure_health_check(autoscaling_elb_health_check_options)
            else
              logger.info("Skip creating ELB instance: #{autoscaling_elb_instance_name}")
            end
          }

          task(:destroy_elb, :roles => :app, :except => { :no_release => true }) {
            if autoscaling_elb_instance and autoscaling_elb_instance.exists?
              if 0 < autoscaling_elb_instance.instances.length
                abort("ELB is not empty.")
              end
              logger.debug("Deleting ELB: #{autoscaling_elb_instance.name}")
              autoscaling_elb_instance.delete()
              logger.debug("Deleted ELB: #{autoscaling_elb_instance.name}")
            end
          }

          task(:update_image, :roles => :app, :except => { :no_release => true }) {
            if autoscaling_create_image
              if autoscaling_image and autoscaling_image.exists?
                logger.debug("Found AMI: #{autoscaling_image.name} (#{autoscaling_image.id})")
              else
                logger.debug("Creating AMI: #{autoscaling_image_name}")
                run("sync; sync; sync") # force flushing to disk
                set(:autoscaling_image, autoscaling_ec2_client.images.create(
                  autoscaling_image_options.merge(:name => autoscaling_image_name, :instance_id => autoscaling_image_instance.id)))
                sleep(autoscaling_wait_interval) until autoscaling_image.exists?
                logger.debug("Created AMI: #{autoscaling_image.name} (#{autoscaling_image.id})")
                [["Name", {:value => autoscaling_image_name}], [autoscaling_image_tag_name]].each do |tag_name, tag_options|
                  begin
                    if tag_options
                      autoscaling_image.add_tag(tag_name, tag_options)
                    else
                      autoscaling_image.add_tag(tag_name)
                    end
                  rescue AWS::EC2::Errors::InvalidAMIID::NotFound => error
                    logger.info("[ERROR] " + error.inspect)
                    sleep(autoscaling_wait_interval)
                    retry
                  end
                end
              end
            else
              logger.info("Skip creating AMI: #{autoscaling_image_name}")
            end
          }

          task(:update_launch_configuration, :roles => :app, :except => { :no_release => true }) {
            if autoscaling_create_launch_configuration
              if autoscaling_launch_configuration.exists?
                logger.debug("Found LaunchConfiguration: #{autoscaling_launch_configuration.name} (#{autoscaling_launch_configuration.image_id})")
              else
                logger.debug("Creating LaunchConfiguration: #{autoscaling_launch_configuration_name} (#{autoscaling_image.id})")
                set(:autoscaling_launch_configuration, autoscaling_autoscaling_client.launch_configurations.create(
                  autoscaling_launch_configuration_name, autoscaling_image.id, autoscaling_launch_configuration_instance_type,
                  autoscaling_launch_configuration_options))
                sleep(autoscaling_wait_interval) unless autoscaling_launch_configuration.exists?
                logger.debug("Created LaunchConfiguration: #{autoscaling_launch_configuration.name} (#{autoscaling_launch_configuration.image_id})")
              end
            else
              logger.info("Skip creating LaunchConfiguration: #{autoscaling_launch_configuration_name}")
            end
          }

          task(:update_group, :roles => :app, :except => { :no_release => true }) {
            if autoscaling_create_group
              if autoscaling_group and autoscaling_group.exists?
                logger.debug("Found AutoScalingGroup: #{autoscaling_group.name} (#{autoscaling_group.launch_configuration_name})")
                autoscaling_group.update(autoscaling_group_options.merge(:launch_configuration => autoscaling_launch_configuration))
              else
                if autoscaling_elb_instance.exists? and autoscaling_launch_configuration.exists?
                  logger.debug("Creating AutoScalingGroup: #{autoscaling_group_name} (#{autoscaling_launch_configuration.name})")
                  set(:autoscaling_group, autoscaling_autoscaling_client.groups.create(autoscaling_group_name,
                    autoscaling_group_options.merge(:launch_configuration => autoscaling_launch_configuration,
                    :load_balancers => [ autoscaling_elb_instance ])))
                  logger.debug("Created AutoScalingGroup: #{autoscaling_group.name} (#{autoscaling_group.launch_configuration_name})")
                else
                  logger.info("Skip creating AutoScalingGroup: #{autoscaling_group_name} (#{autoscaling_launch_configuration_name})")
                end
              end
            else
              logger.info("Skip creating AutoScalingGroup: #{autoscaling_group_name}")
            end
          }

          task(:destroy_group, :roles => :app, :except => { :no_release => true }) {
            if autoscaling_group and autoscaling_group.exists?
              if 0 < autoscaling_group.min_size and 0 < autoscaling_group.max_size
                abort("AutoScalingGroup is not empty.")
              end
              logger.debug("Deleting AutoScalingGroup: #{autoscaling_group.name} (#{autoscaling_group.launch_configuration_name})")
              autoscaling_group.delete()
              logger.debug("Deleted AutoScalingGroup: #{autoscaling_group.name} (#{autoscaling_group.launch_configuration_name})")
            end
          }

          task(:update_policy, :roles => :app, :except => { :no_release => true }) {
            if autoscaling_create_policy
              if autoscaling_expand_policy and autoscaling_expand_policy.exists?
                logger.debug("Found ScalingPolicy for expansion: #{autoscaling_expand_policy.name}")
              else
                logger.debug("Createing ScalingPolicy for expansion: #{autoscaling_expand_policy_name}")
                set(:autoscaling_expand_policy, autoscaling_group.scaling_policies.create(autoscaling_expand_policy_name,
                                                                                          autoscaling_expand_policy_options))
                sleep(autoscaling_wait_interval) unless autoscaling_expand_policy.exists?
                logger.debug("Created ScalingPolicy for expansion: #{autoscaling_expand_policy.name}")
              end
            else
              logger.info("Skip creating ScalingPolicy for expansion: #{autoscaling_expand_policy_name}")
            end

            if autoscaling_create_policy
              if autoscaling_shrink_policy and autoscaling_shrink_policy.exists?
                logger.debug("Found ScalingPolicy for shrinking: #{autoscaling_shrink_policy.name}")
              else
                logger.debug("Createing ScalingPolicy for shrinking: #{autoscaling_shrink_policy_name}")
                set(:autoscaling_shrink_policy, autoscaling_group.scaling_policies.create(autoscaling_shrink_policy_name,
                                                                                          autoscaling_shrink_policy_options))
                sleep(autoscaling_wait_interval) unless autoscaling_shrink_policy.exists?
                logger.debug("Created ScalingPolicy for shrinking: #{autoscaling_shrink_policy.name}")
              end
            else
              logger.info("Skip creating ScalingPolicy for shrinking: #{autoscaling_shrink_policy_name}")
            end
          }

          task(:destroy_policy, :roles => :app, :except => { :no_release => true }) {
            if autoscaling_expand_policy and autoscaling_expand_policy.exists?
              logger.debug("Deleting ScalingPolicy for expansion: #{autoscaling_expand_policy.name}")
              autoscaling_expand_policy.delete()
              logger.debug("Deleted ScalingPolicy for expansion: #{autoscaling_expand_policy.name}")
            end

            if autoscaling_shrink_policy and autoscaling_shrink_policy.exists?
              logger.debug("Deleting ScalingPolicy for shrinking: #{autoscaling_shrink_policy.name}")
              autoscaling_shrink_policy.delete()
              logger.debug("Deleted ScalingPolicy for shrinking: #{autoscaling_shrink_policy.name}")
            end
          }

          def autoscaling_default_alarm_dimensions(namespace)
            case namespace
            when %r{AWS/EC2}i
              [{"Name" => "AutoScalingGroupName", "Value" => autoscaling_group_name}]
            when %r{AWS/ELB}i
              [{"Name" => "LoadBalancerName", "Value" => autoscaling_elb_instance_name}]
            else
              abort("Unknown metric namespace to generate dimensions: #{namespace}")
            end
          end

          task(:update_alarm, :roles => :app, :except => { :no_release => true }) {
            if autoscaling_create_alarm
              autoscaling_expand_alarm_definitions.each do |alarm_name, alarm_options|
                alarm = ( autoscaling_cloudwatch_client.alarms[alarm_name] rescue nil )
                if alarm and alarm.exists?
                  logger.debug("Found Alarm for expansion: #{alarm.name}")
                else
                  logger.debug("Creating Alarm for expansion: #{alarm_name}")
                  options = autoscaling_expand_alarm_options.merge(alarm_options)
                  options[:alarm_actions] = [ autoscaling_expand_policy.arn ] unless options.has_key?(:alarm_actions)
                  options[:dimensions] = autoscaling_default_alarm_dimensions(options[:namespace]) unless options.has_key?(:dimensions)
                  alarm = autoscaling_cloudwatch_client.alarms.create(alarm_name, options)
                  logger.debug("Created Alarm for expansion: #{alarm.name}")
                end
              end
            else
              logger.info("Skip creating Alarm for expansion")
            end

            if autoscaling_create_alarm
              autoscaling_shrink_alarm_definitions.each do |alarm_name, alarm_options|
                alarm = ( autoscaling_cloudwatch_client.alarms[alarm_name] rescue nil )
                if alarm and alarm.exists?
                  logger.debug("Found Alarm for shrinking: #{alarm.name}")
                else
                  logger.debug("Creating Alarm for shrinking: #{alarm_name}")
                  options = autoscaling_shrink_alarm_options.merge(alarm_options)
                  options[:alarm_actions] = [ autoscaling_shrink_policy.arn ] unless options.has_key?(:alarm_actions)
                  options[:dimensions] = autoscaling_default_alarm_dimensions(options[:namespace]) unless options.has_key?(:dimensions)
                  alarm = autoscaling_cloudwatch_client.alarms.create(alarm_name, options)
                  logger.debug("Created Alarm for shrinking: #{alarm.name}")
                end
              end
            else
              logger.info("Skip creating Alarm for shrinking")
            end
          }

          task(:destroy_alarm, :roles => :app, :except => { :no_release => true }) {
            autoscaling_expand_alarm_definitions.each do |alarm_name, alarm_options|
              alarm = ( autoscaling_cloudwatch_client.alarms[alarm_name] rescue nil)
              if alarm and alarm.exists?
                logger.debug("Deleting Alarm for expansion: #{alarm.name}")
                alarm.delete()
                logger.debug("Deleted Alarm for expansion: #{alarm.name}")
              end
            end

            autoscaling_shrink_alarm_definitions.each do |alarm_name, alarm_options|
              alarm = ( autoscaling_cloudwatch_client.alarms[alarm_name] rescue nil )
              if alarm and alarm.exists?
                logger.debug("Deleting Alarm for shrinking: #{alarm.name}")
                alarm.delete()
                logger.debug("Deleted Alarm for shrinking: #{alarm.name}")
              end
            end
          }

          desc("Suspend AutoScaling processes.")
          task(:suspend, :roles => :app, :except => { :no_release => true }) {
            if autoscaling_group and autoscaling_group.exists?
              logger.info("Suspending Group: #{autoscaling_group.name}")
              autoscaling_group.suspend_all_processes
            else
              logger.info("Skip suspending AutoScalingGroup: #{autoscaling_group_name}")
            end
          }

          desc("Resume AutoScaling processes.")
          task(:resume, :roles => :app, :except => { :no_release => true }) {
            if autoscaling_group and autoscaling_group.exists?
              logger.info("Resuming Group: #{autoscaling_group.name}")
              autoscaling_group.resume_all_processes
            else
              logger.info("Skip resuming AutoScalingGroup: #{autoscaling_group_name}")
            end
          }

          desc("Show AutoScaling status.")
          task(:status, :roles => :app, :except => { :no_release => true }) {
            status = {}

            if autoscaling_group and autoscaling_group.exists?
              status[:name] = autoscaling_group.name
              status[:availability_zone_names] = autoscaling_group.availability_zone_names.to_a
              status[:desired_capacity] = autoscaling_group.desired_capacity
              status[:max_size] = autoscaling_group.max_size
              status[:min_size] = autoscaling_group.min_size
            end

            launch_configuration = nil
            if autoscaling_group and autoscaling_group.exists?
              launch_configuration = autoscaling_group.launch_configuration
            elsif autoscaling_launch_configuration and autoscaling_launch_configuration.exists?
              launch_configuration = autoscaling_launch_configuration
            end
            if launch_configuration
               status[:launch_configuration] = {
                :name => launch_configuration.name,
                :iam_instance_profile => launch_configuration.iam_instance_profile,
                :instance_type => launch_configuration.instance_type,
                :security_groups => launch_configuration.security_groups.map { |sg| sg.name },
                :image => {
                  :id => launch_configuration.image.id,
                  :name => launch_configuration.image.name,
                  :state => launch_configuration.image.state,
                }
              }
           end

            load_balancers = nil
            if autoscaling_group and autoscaling_group.exists?
              load_balancers = autoscaling_group.load_balancers.to_a
            elsif autoscaling_elb_instance and autoscaling_elb_instance.exists?
              load_balancers = [ autoscaling_elb_instance ]
            end
            if load_balancers
              status[:load_balancers] = load_balancers.map { |lb|
                {
                  :name => lb.name,
                  :availability_zone_names => lb.availability_zone_names.to_a,
                  :dns_name => lb.dns_name,
                  :instances => lb.instances.map { |i|
                    {
                      :id => i.id,
                      :private_ip_address => i.private_ip_address,
                      :private_dns_name => i.private_dns_name,
                      :public_ip_address => i.public_ip_address,
                      :public_dns_name => i.public_dns_name,
                      :status => i.status,
                    }
                  },
                }
              }
            end

            if autoscaling_group and autoscaling_group.exists?
              status[:scaling_policies] = autoscaling_group.scaling_policies.map { |policy|
                {
                  :name => policy.name,
                  :adjustment_type => policy.adjustment_type,
                  :alarms => policy.alarms.to_hash.keys,
                  :cooldown => policy.cooldown,
                  :scaling_adjustment => policy.scaling_adjustment,
                }
              }
              status[:scheduled_actions] = autoscaling_group.scheduled_actions.map { |action|
                {
                  :name => action.name,
                  :desired_capacity => action.desired_capacity,
                  :end_time => action.end_time,
                  :max_size => action.max_size,
                  :min_size => action.min_size,
                  :start_time => action.start_time,
                }
              }
              status[:suspended_processes] = autoscaling_group.suspended_processes.to_hash
            end

            STDOUT.puts(status.to_yaml)
          }

          desc("Show AutoScaling history.")
          task(:history, :roles => :app, :except => { :no_release => true }) {
            if autoscaling_group and autoscaling_group.exists?
              autoscaling_group.scaling_policies.each do |policy|
                policy.alarms.each do |alarm_name, alarm_arn|
                  alarm = ( autoscaling_cloudwatch_client.alarms[alarm_name] rescue nil )
                  if alarm and alarm.exists?
                    start_date = Time.now - fetch(:autoscaling_history_days, 3) * 86400
                    history_items = alarm.history_items.with_start_date(start_date)

                    STDOUT.puts("--")
                    STDOUT.puts("Alarm: #{alarm_name} (ScalingPolicy: #{policy.name})")
                    history_items.each do |hi|
                      STDOUT.puts("#{hi.timestamp}: #{hi.type}: #{hi.summary}")
                    end
                  end
                end
              end
            else
              abort("AutoScalingGroup is not ready: #{autoscaling_group_name}")
            end

          }

          desc("Delete old AMIs.")
          task(:cleanup, :roles => :app, :except => { :no_release => true }) {
            images = autoscaling_images.sort { |x, y| x.name <=> y.name }
            if autoscaling_group and autoscaling_group.exists?
              images = images.reject { |image| autoscaling_group.launch_configuration.image_id == image.id }
            end
            if autoscaling_image and autoscaling_image.exists?
              images = images.reject { |image| autoscaling_image.id == image.id }
            end
            (images - images.last(autoscaling_keep_images-1)).each do |image|
              if autoscaling_create_image and ( image and image.exists? )
                snapshots = image.block_device_mappings.map { |device, block_device| block_device.snapshot_id }
                logger.debug("Deregistering AMI: #{image.id}")
                image.deregister()
                sleep(autoscaling_wait_interval) unless image.exists?

                snapshots.each do |id|
                  snapshot = autoscaling_ec2_client.snapshots[id]
                  if snapshot and snapshot.exists?
                    logger.debug("Deleting EBS snapshot: #{snapshot.id}")
                    begin
                      snapshot.delete()
                    rescue AWS::EC2::Errors::InvalidSnapshot::InUse => error
                      logger.info("[ERROR] " + error.inspect)
                      sleep(autoscaling_wait_interval)
                      retry
                    end
                  end
                end
              else
                logger.info("Skip deleting AMI: #{image.name} (#{image.id})")
              end

              launch_configuration_name = "#{autoscaling_launch_configuration_name_prefix}#{image.name}"
              launch_configuration = autoscaling_autoscaling_client.launch_configurations[launch_configuration_name]
              if autoscaling_create_launch_configuration and ( launch_configuration and launch_configuration.exists? )
                logger.debug("Deleting LaunchConfiguration: #{launch_configuration.name}")
                launch_configuration.delete()
              else
                logger.info("Skip deleting LaunchConfiguration: #{launch_configuration_name}")
              end
            end
          }
          _cset(:autoscaling_cleanup_after_hooks, ["autoscaling:update"])
          on(:load) {
            [ autoscaling_cleanup_after_hooks ].flatten.each do |t|
              after t, "autoscaling:cleanup" if t
            end
          }
        }
      }
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::AutoScaling)
end

# vim:set ft=ruby ts=2 sw=2 :
