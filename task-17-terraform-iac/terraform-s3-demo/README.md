# Terraform S3 Demo

Session 18, Task 1. An S3 bucket created with Terraform, with the full command workflow
documented.

## Important: this was planned, not applied

`init`, `fmt`, `validate` and `plan` were all run for real against a live AWS account.
**`apply` was deliberately not run.**

`plan` makes read-only API calls and costs nothing. `apply` creates real resources and
starts billing, and that is a decision for the account owner rather than something to do
unattended. The `apply` and `destroy` sections below give the exact commands and what to
expect; run them when you are ready to spend, and run `destroy` straight afterwards.

An S3 bucket with nothing in it costs essentially nothing, so this is a cheap one to
actually apply — unlike the EC2 and NAT gateway resources in session 19.

## File layout

    terraform-s3-demo/
    ├── provider.tf                 provider and version constraints
    ├── variables.tf                input variables with defaults and validation
    ├── main.tf                     the bucket and its settings
    ├── outputs.tf                  values exposed after apply
    ├── terraform.tfvars.example    template; copy to terraform.tfvars
    ├── .gitignore                  keeps state and real tfvars out of git
    └── README.md

Splitting the configuration this way is convention rather than requirement — Terraform
reads every `.tf` file in the directory and builds one graph regardless of filenames. The
split exists so a reader knows where to look.

## What it creates

Eight resources, which is more than "a bucket" because a bucket's settings are separate
resources in the AWS provider:

| Resource | Purpose |
|---|---|
| `random_id.suffix` | four random bytes appended to the name |
| `aws_s3_bucket.demo` | the bucket itself |
| `aws_s3_bucket_versioning.demo` | keeps every object version |
| `aws_s3_bucket_server_side_encryption_configuration.demo` | AES256 at rest |
| `aws_s3_bucket_public_access_block.demo` | blocks all public access |
| `aws_s3_bucket_ownership_controls.demo` | disables legacy ACLs |
| `aws_s3_bucket_lifecycle_configuration.demo` | expires old versions, aborts stale multipart uploads |
| `aws_s3_bucket_policy.demo` | denies any non-TLS request |

The random suffix is not decoration. S3 bucket names are globally unique across every AWS
account, so any fixed name in shared example code will already be taken.

## The workflow

### terraform init

Downloads the providers and writes the dependency lock file.

![init, fmt and validate](../screenshots/18-01-init-validate.png)

    $ terraform init
    Terraform has been successfully initialized!

Run it again whenever providers or backend configuration change. Everything else refuses to
run until it has been.

### terraform fmt

Rewrites files to canonical formatting. `-check` reports instead of rewriting, which is what
belongs in CI.

    $ terraform fmt -check
    all files formatted

No output means nothing needed changing.

### terraform validate

Checks syntax and internal consistency — types, required arguments, references that resolve.
It does **not** talk to AWS, so it cannot catch a bucket name already in use or a missing
permission.

    $ terraform validate
    Success! The configuration is valid.

### terraform plan

Compares the configuration against state and against reality, then prints what it would do.
This is the step that talks to AWS, read-only.

![terraform plan](../screenshots/18-02-plan.png)

    # aws_s3_bucket.demo will be created
    # aws_s3_bucket_lifecycle_configuration.demo will be created
    # aws_s3_bucket_ownership_controls.demo will be created
    # aws_s3_bucket_policy.demo will be created
    # aws_s3_bucket_public_access_block.demo will be created
    # aws_s3_bucket_server_side_encryption_configuration.demo will be created
    # aws_s3_bucket_versioning.demo will be created
    # random_id.suffix will be created

    Plan: 8 to add, 0 to change, 0 to destroy.

The summary line is the thing to read. `0 to change, 0 to destroy` on a first run is
expected; a `destroy` count you did not intend is the warning sign.

Note how many values are `(known after apply)` — the bucket name depends on the random ID,
which does not exist yet. Terraform tracks these unknowns through the graph.

For anything real, save the plan and apply exactly that:

    terraform plan -out=tfplan
    terraform apply tfplan

Otherwise `apply` re-plans, and what it does may differ from what you reviewed.

### terraform apply

**Not run here.** Creates the resources.

    $ terraform apply
    ...
    Plan: 8 to add, 0 to change, 0 to destroy.
    Do you want to perform these actions?
      Enter a value: yes

    Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Terraform works out the order from the references: `random_id` before the bucket, because
the name interpolates it; the bucket before everything that takes `bucket = aws_s3_bucket.demo.id`.
Nothing declares that ordering explicitly — it falls out of the dependency graph, which is
the central idea of the tool.

`depends_on` appears twice in `main.tf` for the two cases the graph cannot infer: the
lifecycle rule must come after versioning is enabled, and the bucket policy after public
access is blocked.

### terraform show

Prints the current state in human-readable form.

    terraform show

Useful after apply to see the attributes AWS filled in — the resolved bucket name, the ARN,
the region.

### terraform output

Prints just the declared outputs.

    $ terraform output
    bucket_arn        = "arn:aws:s3:::scaler-devops-demo-a1b2c3d4"
    bucket_name       = "scaler-devops-demo-a1b2c3d4"
    bucket_region     = "ap-south-1"
    versioning_status = "Enabled"

    $ terraform output -raw bucket_name
    scaler-devops-demo-a1b2c3d4

`-raw` gives an unquoted value, which is what you pipe into other commands in a script.

### terraform destroy

**Run this when finished.** Removes everything in state.

    terraform destroy

A bucket must be empty to be deleted. If objects were uploaded, `destroy` fails with
`BucketNotEmpty` and they must be removed first:

    aws s3 rm s3://$(terraform output -raw bucket_name) --recursive

With versioning enabled, deleting the visible objects is not enough — every noncurrent
version and delete marker must go too. `force_destroy = true` on the bucket resource makes
Terraform handle that, and is deliberately left off here so the failure is instructive
rather than silent.

## State

`terraform.tfstate` maps the configuration to real resource IDs. It is how Terraform knows
that `aws_s3_bucket.demo` means that specific bucket.

Two consequences:

**It can contain secrets.** State holds every attribute, including ones marked sensitive.
It is gitignored here for that reason.

**Local state does not work for a team.** Two people applying at once will corrupt it. The
fix is remote state in S3 with a DynamoDB lock table:

    terraform {
      backend "s3" {
        bucket         = "my-tf-state"
        key            = "s3-demo/terraform.tfstate"
        region         = "ap-south-1"
        dynamodb_table = "terraform-locks"
        encrypt        = true
      }
    }

Which is its own chicken-and-egg problem: the state bucket has to be created before it can
hold state.

## Variables

Defined in `variables.tf` with defaults, so the configuration runs with no input. Precedence,
lowest to highest: default, `terraform.tfvars`, `*.auto.tfvars`, `TF_VAR_` environment
variables, `-var` on the command line.

`bucket_name_prefix` carries a validation block rejecting anything but lowercase letters,
digits and hyphens — S3's naming rules enforced before AWS rejects it.

`terraform.tfvars` is gitignored and `terraform.tfvars.example` is committed, which is the
standard way to share the shape of the configuration without the values.

## Credentials

Terraform uses the standard AWS credential chain — environment variables, shared config,
instance or container roles. Nothing about credentials appears in any `.tf` file here, and
nothing should.

    $ aws sts get-caller-identity --query Account --output text
    <account-id>

For CI, OIDC federation into a role is better than access keys: no long-lived secret exists
to leak, as covered in the IAM notes in `../aws-services/01-iam/`.
