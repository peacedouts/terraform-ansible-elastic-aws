data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name_prefix}-node"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Lets the SSM agent register the instance so Session Manager (and Ansible's
# aws_ssm connection plugin) can reach it without SSH.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# No S3 permissions here on purpose. The aws_ssm connection plugin hands nodes
# presigned URLs for the transfer bucket, so they never need their own access.
# Granting it would let one node read or overwrite files meant for another.

resource "aws_iam_instance_profile" "node" {
  name = "${var.name_prefix}-node"
  role = aws_iam_role.node.name
}
