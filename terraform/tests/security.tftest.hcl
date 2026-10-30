# Offline tests: providers are mocked, so no AWS credentials or resources are
# needed. Run with `terraform test` (Terraform >= 1.7).

mock_provider "aws" {
  # The provider still validates policy JSON when mocked, so give every
  # policy document a minimal valid one.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"ec2.amazonaws.com\"}}]}"
    }
  }

  # ARNs are validated too, so mocked ones must be well formed.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      arn = "arn:aws:iam::123456789012:instance-profile/mock"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mock-bucket"
    }
  }
}

override_data {
  target = data.aws_availability_zones.available
  values = {
    names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
  }
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
  }
}

override_data {
  target = data.aws_ssm_parameter.ami
  values = {
    value = "ami-0123456789abcdef0"
  }
}

# Keeps the test from writing inventory files into the repo.
mock_provider "local" {}

variables {
  region      = "us-east-1"
  name_prefix = "elk-test"
}

run "default_layout" {
  command = apply

  assert {
    condition     = length(aws_instance.node) == 5
    error_message = "Expected 3 Elasticsearch nodes, 1 Kibana and 1 Logstash."
  }

  assert {
    condition     = length([for i in aws_instance.node : i if i.tags.ElkRole == "elasticsearch"]) == 3
    error_message = "Expected 3 Elasticsearch nodes by default."
  }

  assert {
    condition     = length(distinct([for i in aws_instance.node : i.subnet_id if i.tags.ElkRole == "elasticsearch"])) == 3
    error_message = "Elasticsearch nodes should be spread across three subnets (one per AZ)."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "single_nat_gateway = true should create exactly one NAT gateway."
  }
}

run "instances_are_private_and_hardened" {
  command = apply

  assert {
    condition     = alltrue([for i in aws_instance.node : i.associate_public_ip_address == false])
    error_message = "No instance may have a public IP."
  }

  assert {
    condition     = alltrue([for i in aws_instance.node : i.metadata_options[0].http_tokens == "required"])
    error_message = "IMDSv2 must be required on every instance."
  }

  assert {
    condition     = alltrue([for i in aws_instance.node : i.metadata_options[0].http_put_response_hop_limit == 1])
    error_message = "IMDS hop limit must be 1 so containers can't reach instance credentials."
  }

  assert {
    condition     = alltrue([for i in aws_instance.node : i.root_block_device[0].encrypted == true])
    error_message = "Every root volume must be encrypted."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "Public subnets must not auto-assign public IPs."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.map_public_ip_on_launch == false])
    error_message = "Private subnets must not auto-assign public IPs."
  }
}

run "no_ingress_from_cidrs" {
  command = apply

  assert {
    condition = alltrue(concat(
      [aws_vpc_security_group_ingress_rule.es_transport.cidr_ipv4 == null],
      [for r in aws_vpc_security_group_ingress_rule.es_http : r.cidr_ipv4 == null && r.cidr_ipv6 == null],
      [for r in aws_vpc_security_group_ingress_rule.logstash_beats : r.cidr_ipv4 == null && r.cidr_ipv6 == null],
    ))
    error_message = "Ingress must reference security groups, never CIDR ranges."
  }

  assert {
    condition = alltrue(concat(
      [aws_vpc_security_group_ingress_rule.es_transport.from_port != 22],
      [for r in aws_vpc_security_group_ingress_rule.es_http : r.from_port != 22],
      [for r in aws_vpc_security_group_ingress_rule.logstash_beats : r.from_port != 22],
    ))
    error_message = "There must be no SSH ingress; access is through SSM."
  }

  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0
    error_message = "The default security group must allow nothing."
  }
}

run "transfer_bucket_is_locked_down" {
  command = apply

  assert {
    condition = (
      aws_s3_bucket_public_access_block.ssm_transfer.block_public_acls &&
      aws_s3_bucket_public_access_block.ssm_transfer.block_public_policy &&
      aws_s3_bucket_public_access_block.ssm_transfer.ignore_public_acls &&
      aws_s3_bucket_public_access_block.ssm_transfer.restrict_public_buckets
    )
    error_message = "All four S3 public access blocks must be on."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.ssm_transfer.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled on the transfer bucket."
  }

  assert {
    condition     = one([for r in aws_s3_bucket_lifecycle_configuration.ssm_transfer.rule : r.expiration[0].days]) == 1
    error_message = "Transfer objects should expire after one day."
  }
}

run "generated_inventory_targets_this_stack" {
  command = apply

  assert {
    condition     = strcontains(local_file.ansible_inventory.content, "tag:ElkStack: elk-test")
    error_message = "The generated inventory must filter on this stack's tag."
  }

  assert {
    condition     = strcontains(local_file.ansible_inventory.content, "ansible_host: instance_id")
    error_message = "The generated inventory must address hosts by instance ID for SSM."
  }
}

run "single_node_layout" {
  command = apply

  variables {
    es_node_count      = 1
    az_count           = 1
    single_nat_gateway = false
  }

  assert {
    condition     = length(aws_instance.node) == 3
    error_message = "Single-node mode should create 1 Elasticsearch node, 1 Kibana and 1 Logstash."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "One AZ means one NAT gateway, even when single_nat_gateway is false."
  }
}

run "rejects_even_node_count" {
  command = plan

  variables {
    es_node_count = 2
  }

  expect_failures = [var.es_node_count]
}

run "rejects_bad_name_prefix" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}
