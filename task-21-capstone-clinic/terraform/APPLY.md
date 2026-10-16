# Running the EKS infrastructure

I am blocked from running `terraform apply` by a safety rule that stops an agent
provisioning cloud infrastructure unsupervised. `terraform init`, `validate`
and `plan` have already been run — the plan is saved at `tfplan` and shows
**54 to add, 0 to change, 0 to destroy**. These are the exact commands to
finish it, with what to capture at each step.

## Cost

| | |
|---|---|
| EKS control plane | ~$0.10/hour |
| 2 × t3.medium workers | ~$0.08/hour |
| NAT gateway | ~$0.05/hour + data |
| **Total** | **~$0.23/hour** |

Create and destroy in one sitting and it costs well under a dollar. Leave it
running for a week and it is roughly $40.

## The sequence

    cd task-21-capstone-clinic/terraform
    terraform apply tfplan

(The plan file above was generated against the committed config. If any
terraform file has changed since, regenerate it first with
`terraform plan -out=tfplan`.)

**This takes 15–20 minutes.** EKS control plane creation is slow and there is
nothing wrong if it sits on `module.eks.aws_eks_cluster.this[0]: Still creating...`
for ten minutes.

Expect:

    Apply complete! Resources: 54 added, 0 changed, 0 destroyed.

    Outputs:
    cluster_endpoint  = "https://XXXX.gr7.ap-south-1.eks.amazonaws.com"
    cluster_name      = "clinic-eks"
    configure_kubectl = "aws eks update-kubeconfig --region ap-south-1 --name clinic-eks"

## What to capture for M7

1. **`terraform plan` output** — the summary line is enough.
2. **AWS Console screenshot** of the EKS cluster. Console → EKS → Clusters →
   `clinic-eks`. The rubric asks for this specifically.
3. **`terraform destroy` output** — the `Destroy complete!` line.

Save them into `../screenshots/` as `M7-01-tf-apply.png`,
`M7-02-eks-console.png` and `M7-03-tf-destroy.png`.

## Optionally, deploy the app to the real cluster

This is not required by the rubric — M8 is already evidenced on the local kind
cluster — but it makes the story complete:

    aws eks update-kubeconfig --region ap-south-1 --name clinic-eks
    kubectl get nodes

    helm install clinic ../helm/clinic \
      --namespace clinic --create-namespace \
      --set image.registry=ghcr.io \
      --set image.repository=mahirabidi12/devops-assignment-clinic \
      --set image.backendTag=latest --set image.frontendTag=latest

    kubectl get pods -n clinic

Note the images must be public in GHCR, or the cluster needs an
`imagePullSecret`. By default a GHCR package is private.

## Then tear it down

    terraform destroy

Expect `Destroy complete! Resources: 54 destroyed.` This also takes 10–15
minutes.

**Confirm it finished.** An interrupted destroy leaves the control plane and the
NAT gateway billing. Check with:

    terraform state list        # should be empty
    aws eks list-clusters --region ap-south-1

The NAT gateway and the EKS control plane are the two that cost real money if
they survive, so it is worth looking in the console as well.
