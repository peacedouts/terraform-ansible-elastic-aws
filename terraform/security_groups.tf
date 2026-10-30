# One security group per role. Rules reference other groups rather than CIDRs,
# so only the components that need a port can reach it. There are no SSH rules:
# all administrative access goes through SSM Session Manager.

resource "aws_security_group" "elasticsearch" {
  name        = "${var.name_prefix}-elasticsearch"
  description = "Elasticsearch nodes"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-elasticsearch" }
}

resource "aws_security_group" "kibana" {
  name        = "${var.name_prefix}-kibana"
  description = "Kibana"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-kibana" }
}

resource "aws_security_group" "logstash" {
  name        = "${var.name_prefix}-logstash"
  description = "Logstash"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-logstash" }
}

locals {
  all_stack_sgs = {
    elasticsearch = aws_security_group.elasticsearch.id
    kibana        = aws_security_group.kibana.id
    logstash      = aws_security_group.logstash.id
  }
}

# --- Elasticsearch -----------------------------------------------------------

# Node-to-node transport.
resource "aws_vpc_security_group_ingress_rule" "es_transport" {
  security_group_id            = aws_security_group.elasticsearch.id
  referenced_security_group_id = aws_security_group.elasticsearch.id
  ip_protocol                  = "tcp"
  from_port                    = 9300
  to_port                      = 9300
  description                  = "ES transport between cluster nodes"
}

# HTTPS API from every stack component (ES itself, Kibana, Logstash, and Metricbeat on each host).
resource "aws_vpc_security_group_ingress_rule" "es_http" {
  for_each = local.all_stack_sgs

  security_group_id            = aws_security_group.elasticsearch.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 9200
  to_port                      = 9200
  description                  = "ES HTTPS API from ${each.key}"
}

# --- Logstash ----------------------------------------------------------------

# Beats input from Filebeat running on every stack host.
resource "aws_vpc_security_group_ingress_rule" "logstash_beats" {
  for_each = local.all_stack_sgs

  security_group_id            = aws_security_group.logstash.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5044
  to_port                      = 5044
  description                  = "Beats input from ${each.key}"
}

# --- Kibana ------------------------------------------------------------------
# No ingress rules. Users reach Kibana with SSM port forwarding, which tunnels
# through the SSM agent and does not need an open port.

# --- Egress ------------------------------------------------------------------
# Outbound HTTPS (package repos, SSM endpoints, S3) plus intra-VPC traffic.

resource "aws_vpc_security_group_egress_rule" "https_out" {
  for_each = local.all_stack_sgs

  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS out for packages, SSM and S3"
}

# Ubuntu's default apt mirrors are plain HTTP (packages are still GPG-verified).
resource "aws_vpc_security_group_egress_rule" "http_out" {
  for_each = local.all_stack_sgs

  security_group_id = each.value
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP out for Ubuntu apt mirrors"
}

resource "aws_vpc_security_group_egress_rule" "vpc_out" {
  for_each = local.all_stack_sgs

  security_group_id = each.value
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
  description       = "All traffic within the VPC"
}
