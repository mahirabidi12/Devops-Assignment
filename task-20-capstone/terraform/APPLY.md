# Running the EKS infrastructure

I am blocked from running `terraform apply` by a safety rule that stops an agent
provisioning cloud infrastructure unsupervised. These are the exact commands,
in order, with what to capture at each step.

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

    cd task-20-capstone/terraform
    cp terraform.tfvars.example terraform.tfvars

    terraform init
    terraform validate
    terraform plan -out=tfplan

Check the plan summary before continuing. Expect roughly 60 resources — the VPC
module and the EKS module each create many.

    terraform apply tfplan

**This takes 15–20 minutes.** EKS control plane creation is slow and there is
nothing wrong if it sits on `module.eks.aws_eks_cluster.this[0]: Still creating...`
for ten minutes.

Expect:

    Apply complete! Resources: NN added, 0 changed, 0 destroyed.

    Outputs:
    cluster_endpoint  = "https://XXXX.gr7.ap-south-1.eks.amazonaws.com"
    cluster_name      = "taskboard-eks"
    configure_kubectl = "aws eks update-kubeconfig --region ap-south-1 --name taskboard-eks"

## What to capture for M7

1. **`terraform plan` output** — the summary line is enough.
2. **AWS Console screenshot** of the EKS cluster. Console → EKS → Clusters →
   `taskboard-eks`. The rubric asks for this specifically.
3. **`terraform destroy` output** — the `Destroy complete!` line.

Save them into `../screenshots/` as `21-10-tf-apply.png`,
`21-11-eks-console.png` and `21-12-tf-destroy.png`.

## Optionally, deploy the app to the real cluster

This is not required by the rubric — M8 is already evidenced on the local kind
cluster — but it makes the story complete:

    aws eks update-kubeconfig --region ap-south-1 --name taskboard-eks
    kubectl get nodes

    helm install taskboard ../helm/taskboard \
      --namespace taskboard --create-namespace \
      --set image.registry=ghcr.io \
      --set image.repository=mahirabidi12/devops-assignment-taskboard \
      --set image.backendTag=latest --set image.frontendTag=latest

    kubectl get pods -n taskboard

Note the images must be public in GHCR, or the cluster needs an
`imagePullSecret`. By default a GHCR package is private.

## Then tear it down

    terraform destroy

Expect `Destroy complete! Resources: NN destroyed.` This also takes 10–15
minutes.

**Confirm it finished.** An interrupted destroy leaves the control plane and the
NAT gateway billing. Check with:

    terraform state list        # should be empty
    aws eks list-clusters --region ap-south-1

The NAT gateway and the EKS control plane are the two that cost real money if
they survive, so it is worth looking in the console as well.
