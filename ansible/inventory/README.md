# Inventory

Nothing in here is hand-maintained.

- `elk.aws_ec2.yml` is written by `terraform apply`. It uses the `amazon.aws.aws_ec2`
  plugin to find running instances tagged with this stack's `ElkStack` tag and groups
  them by their `ElkRole` tag (`elasticsearch`, `kibana`, `logstash`). Each host's
  `ansible_host` is its instance ID, which is what the `aws_ssm` connection plugin needs.
- `group_vars/all/terraform.yml` is also written by Terraform (region, transfer bucket,
  cluster name).
- `group_vars/all/vault.yml` holds secrets. Create it with `make vault`. It is
  gitignored; `vault.yml.example` shows the variable names.

Check what Ansible sees with:

```bash
ansible-inventory --graph
```
