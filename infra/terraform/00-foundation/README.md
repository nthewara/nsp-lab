# 00-foundation

This stage is **NOT** Terraform — it's a shell script that creates the dedicated state storage:

```bash
./scripts/00-bootstrap-state.sh
```

The script creates:

- RG `tfstate-nsp-lab` (in `australiaeast`)
- Storage account `tfstatensplab<6 random chars>` (Standard_LRS, key-disabled-friendly via Entra)
- Container `tfstate`
- A `~/workspace/tfvars/nsp-lab-backend.hcl` file with the backend config (gitignored)

That backend file is what every other TF stage (`10-…`, `20-…`, etc.) consumes via `terraform init -backend-config=…`.

If you need to start over, delete the RG with `az group delete -n tfstate-nsp-lab -y` and re-run the bootstrap.
