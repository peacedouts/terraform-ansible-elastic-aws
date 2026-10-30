variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for resource names and the Project tag. Also used as the Elasticsearch cluster name."
  type        = string
  default     = "elk-demo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.name_prefix))
    error_message = "name_prefix must be 3-21 chars of lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread subnets and nodes across."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "az_count must be between 1 and 3."
  }
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all private subnets (cheaper) instead of one per AZ (more resilient)."
  type        = bool
  default     = true
}

variable "es_node_count" {
  description = "Number of Elasticsearch nodes. Use an odd number (1 or 3+) so master elections have a quorum."
  type        = number
  default     = 3

  validation {
    condition     = var.es_node_count >= 1 && var.es_node_count % 2 == 1
    error_message = "es_node_count must be an odd number >= 1."
  }
}

variable "es_instance_type" {
  description = "Instance type for Elasticsearch nodes."
  type        = string
  default     = "m6i.large"
}

variable "es_volume_size_gb" {
  description = "Root volume size for Elasticsearch nodes, in GiB."
  type        = number
  default     = 50
}

variable "kibana_instance_type" {
  description = "Instance type for the Kibana node."
  type        = string
  default     = "t3.medium"
}

variable "logstash_instance_type" {
  description = "Instance type for the Logstash node."
  type        = string
  default     = "t3.large"
}

variable "default_volume_size_gb" {
  description = "Root volume size for Kibana and Logstash nodes, in GiB."
  type        = number
  default     = 20
}

variable "ami_ssm_parameter" {
  description = "Public SSM parameter that resolves to the AMI ID. Defaults to the latest Ubuntu 24.04 LTS from Canonical."
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to CloudWatch Logs."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "How long to keep VPC flow logs."
  type        = number
  default     = 14
}

variable "extra_tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
