data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

locals {
  ami_id = nonsensitive(data.aws_ssm_parameter.ami.value)

  # Every node shares these settings; only size, subnet and role differ.
  nodes = merge(
    {
      for i in range(var.es_node_count) :
      format("%s-es-%02d", var.name_prefix, i + 1) => {
        role          = "elasticsearch"
        instance_type = var.es_instance_type
        volume_size   = var.es_volume_size_gb
        subnet_id     = aws_subnet.private[i % var.az_count].id
        sg_id         = aws_security_group.elasticsearch.id
      }
    },
    {
      "${var.name_prefix}-kibana-01" = {
        role          = "kibana"
        instance_type = var.kibana_instance_type
        volume_size   = var.default_volume_size_gb
        subnet_id     = aws_subnet.private[0].id
        sg_id         = aws_security_group.kibana.id
      }
      "${var.name_prefix}-logstash-01" = {
        role          = "logstash"
        instance_type = var.logstash_instance_type
        volume_size   = var.default_volume_size_gb
        subnet_id     = aws_subnet.private[1 % var.az_count].id
        sg_id         = aws_security_group.logstash.id
      }
    },
  )
}

resource "aws_instance" "node" {
  for_each = local.nodes

  ami                    = local.ami_id
  instance_type          = each.value.instance_type
  subnet_id              = each.value.subnet_id
  vpc_security_group_ids = [each.value.sg_id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  associate_public_ip_address = false
  ebs_optimized               = true
  monitoring                  = true

  # IMDSv2 only.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = each.value.volume_size
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name     = each.key
    ElkRole  = each.value.role
    ElkStack = var.name_prefix
  }

  # A new AMI release shouldn't force replacement of a running cluster.
  lifecycle {
    ignore_changes = [ami]
  }
}
