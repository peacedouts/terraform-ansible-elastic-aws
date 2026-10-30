data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Only the first az_count zones are used (slice), so a new AZ doesn't move existing subnets.
  state = "available"

  # Local Zones and Wavelength Zones aren't suitable for this stack.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /20 subnets: public in the first block, private further up so they are easy to tell apart.
  public_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  nat_gateway_count = var.single_nat_gateway ? 1 : var.az_count
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# Lock down the default security group so nothing accidentally uses it.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-default-deny" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

# Public subnets only hold the NAT gateways. No instances get public IPs.
resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.name_prefix}-public-${local.azs[count.index]}" }
}

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.private_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.name_prefix}-private-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name_prefix}-public" }
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-nat-${count.index}" }
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags       = { Name = "${var.name_prefix}-nat-${count.index}" }
  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = { Name = "${var.name_prefix}-private-${local.azs[count.index]}" }
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# --- VPC flow logs -----------------------------------------------------------

resource "aws_cloudwatch_log_group" "flow_logs" {
  #checkov:skip=CKV_AWS_158:CloudWatch Logs encrypts at rest by default; a CMK is overkill for a demo stack.
  #checkov:skip=CKV_AWS_338:Retention is a variable; 14 days keeps demo costs down. Raise it for production.
  count = var.enable_flow_logs ? 1 : 0

  name              = "/vpc/${var.name_prefix}/flow-logs"
  retention_in_days = var.flow_logs_retention_days
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name               = "${var.name_prefix}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
}
