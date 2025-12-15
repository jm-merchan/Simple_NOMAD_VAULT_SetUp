# Boundary Egress Worker Configuration

This Terraform configuration deploys a Boundary egress worker on ubuntu_remote via Nomad.

## Prerequisites

Set the following environment variables:
```bash
export VAULT_ADDR="https://vault-eu-west-2-yfrs.jose-merchan.sbx.hashidemos.io:8200"
export VAULT_TOKEN="your-vault-token"
export NOMAD_ADDR="https://nomad-eu-west-2-yfrs.jose-merchan.sbx.hashidemos.io"
export NOMAD_TOKEN="your-nomad-token"
```

## Deployment

The ingress worker address is automatically retrieved from `../3_boundary_deploy_aws/terraform.tfstate`.

```bash
terraform init
terraform apply
```

## Verification

```bash
# Check Nomad job status
nomad job status boundary-egress-worker

# View logs
nomad alloc logs -f $(nomad job allocs boundary-egress-worker | grep running | head -1 | awk '{print $1}')
```
