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

# The aws_ssm connection plugin moves files through S3. Nodes only get access
# to the dedicated transfer bucket.
data "aws_iam_policy_document" "ssm_transfer" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.ssm_transfer.arn}/*"]
  }

  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.ssm_transfer.arn]
  }
}

resource "aws_iam_role_policy" "ssm_transfer" {
  name   = "ssm-transfer-bucket"
  role   = aws_iam_role.node.id
  policy = data.aws_iam_policy_document.ssm_transfer.json
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name_prefix}-node"
  role = aws_iam_role.node.name
}
