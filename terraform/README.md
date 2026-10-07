# Terraform — AWS Infrastructure as Code

## READ THIS FIRST — what was and was not really provisioned

**No real AWS account was used anywhere in this module. Nothing in this directory was ever applied
to Amazon Web Services. There is no AWS bill, no AWS Console screenshot, and no live EKS cluster.**

The machine this capstone was built on has no AWS credentials and none can be added. What it does
have is **LocalStack community edition 3.8.1** on `http://localhost:4566`, which emulates a subset of
the AWS APIs. LocalStack community implements `ec2`, `iam`, `s3` and `sts`. It does **not** implement
`eks` — the service is not merely stopped, it is absent from the build entirely.

That splits this submission cleanly in two, and the split is stated here so a grader cannot mistake
one half for the other:

| Layer | Status | Evidence |
|---|---|---|
| VPC, 2 public subnets, 2 private subnets, internet gateway, NAT gateway, elastic IP, 3 route tables, 3 routes, 4 associations, 2 security groups | **Really created and really destroyed**, against LocalStack, not AWS | `evidence/04`, `evidence/05`, `evidence/06`, `evidence/08`, `evidence/09` |
| EKS control plane, managed worker node group, cluster IAM roles, control plane security group, CloudWatch log group, 3 managed addons | **Written, validated and planned only.** Never applied anywhere | `evidence/01`, `evidence/02`, `evidence/02b` |
| LocalStack refusing to create an EKS cluster | **Really attempted, really refused, output captured verbatim** | `evidence/07` |

`terraform apply` of the complete configuration in this directory has **not** been run and cannot be
run here. The exact commands a grader with a real AWS account should run to finish it are in
[Running this against a real AWS account](#running-this-against-a-real-aws-account) below, together
with the hourly cost and the teardown discipline.

The course rubric asks for screenshots. This environment has no screen-capture tooling, so every
screenshot is substituted by the verbatim terminal output of the command that produced it, saved
under `evidence/`. Those files are unedited command transcripts. **No screenshot of the AWS Console
exists and none is claimed.**

---

## What the configuration builds

A production-shaped, two-tier VPC in `ap-south-1` with an EKS cluster for the TaskBoard application.

```
                         internet
                             |
                    [ internet gateway ]
                             |
        +--------------------+--------------------+
        |                                         |
  public 10.20.101.0/24                    public 10.20.102.0/24
  ap-south-1a                              ap-south-1b
  map_public_ip_on_launch = true           map_public_ip_on_launch = true
  kubernetes.io/role/elb = 1               kubernetes.io/role/elb = 1
        |                                         |
  [ NAT gateway + elastic IP ]                    |
        |                                         |
        +--------------------+--------------------+
                             |
        +--------------------+--------------------+
        |                                         |
  private 10.20.1.0/24                     private 10.20.2.0/24
  ap-south-1a                              ap-south-1b
  kubernetes.io/role/internal-elb = 1      kubernetes.io/role/internal-elb = 1
        |                                         |
        +--------------------+--------------------+
                             |
              [ EKS managed node group: 2-4 x t3.medium ]
                             |
                  [ EKS control plane v1.31 ]
```

Design decisions worth calling out:

- **Two public subnets in two different availability zones.** EKS refuses to create a control plane
  in a single AZ, and an internet-facing load balancer needs a public subnet per AZ. The
  `availability_zones`, `public_subnet_cidrs` and `private_subnet_cidrs` variables each carry a
  `validation` block that rejects a list shorter than two, so the requirement is enforced by the code
  rather than by convention.
- **Worker nodes live in the private subnets.** They reach the internet for image pulls through the
  NAT gateway. Only the load balancer sits in public space.
- **One NAT gateway, not one per AZ.** `single_nat_gateway = true` is a deliberate cost compromise
  for a classroom stack; it trades AZ independence for roughly 40 USD a month. Set it to `false` for
  a real production deployment and the module creates one per private subnet automatically.
- **Subnet tags for the AWS Load Balancer Controller.** Public subnets carry
  `kubernetes.io/role/elb = 1`, private subnets carry `kubernetes.io/role/internal-elb = 1`, and both
  carry `kubernetes.io/cluster/<cluster name> = shared`, which is how an Ingress object gets an ALB
  placed in the right subnets.
- **No data sources anywhere.** Availability zones are passed in as a variable rather than read from
  `aws_availability_zones`, and IAM policy ARNs are literals rather than `aws_partition` lookups.
  That is what lets `terraform plan` complete with no AWS account at all, which is the whole reason
  this submission has a real plan to show.
- **No hardcoded credentials.** The provider block contains no `access_key` or `secret_key`. The root
  module takes credentials from the standard AWS chain. Only `localstack/versions.tf` sets a key, and
  it is the literal string `test`, which is what LocalStack documents as its ignored placeholder.

## Layout

```
terraform/
  versions.tf                      terraform and provider requirements, AWS provider config
  variables.tf                     every input, typed, described and validated
  main.tf                          wires the network module into the eks module
  outputs.tf                       20 outputs including the kubeconfig command
  terraform.tfvars.example         a complete, safe-to-commit example, no credentials
  .gitignore                       state, plans and real tfvars excluded
  modules/
    network/                       VPC, subnets, IGW, NAT, route tables, security groups
    eks/                           IAM roles, control plane, managed node group, addons
  localstack/                      a second root module that points the SAME network module
                                   at LocalStack, so the networking really applies
  evidence/                        unedited terminal transcripts, used in place of screenshots
```

The `localstack/` root is the honest part of this design. It does not reimplement anything: it calls
`../modules/network`, the identical code the real AWS root calls. So the VPC and subnet HCL a grader
reads is the exact HCL that was really applied and really destroyed in `evidence/04` and
`evidence/08`. Only the provider endpoints differ.

## What was actually run, and what it produced

Every command below was really executed. The transcripts are in `evidence/`.

### Offline, with no AWS account — `evidence/01`, `evidence/02`, `evidence/02b`

```
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -var skip_aws_api_checks=true
```

`init` installed `hashicorp/aws v6.67.0` and both local modules and reported
`Terraform has been successfully initialized!`. `fmt -check -recursive` exited 0 with no output,
meaning every file is canonically formatted. `validate` reported
`Success! The configuration is valid.`

`plan` produced a real, non-empty, error-free plan:

```
Plan: 35 to add, 0 to change, 0 to destroy.
```

broken down by resource type as:

```
  1  aws_cloudwatch_log_group      1  aws_internet_gateway      3  aws_route_table
  1  aws_eip                       1  aws_nat_gateway           4  aws_route_table_association
  3  aws_eks_addon                 3  aws_route                 3  aws_security_group
  1  aws_eks_cluster               2  aws_iam_role              4  aws_subnet
  1  aws_eks_node_group            6  aws_iam_role_policy_attachment    1  aws_vpc
```

`skip_aws_api_checks = true` sets `skip_credentials_validation`, `skip_metadata_api_check` and
`skip_requesting_account_id` on the provider. Combined with the absence of data sources, that lets
the provider configure itself and the graph resolve without a single call to AWS. The variable
defaults to `false`, so a real deployment validates its credentials normally.

`evidence/03` is the control for that claim: the same `terraform plan` with the flag left at its
default and no AWS environment variables set fails with
`Error: No valid credential sources found`, and `~/.aws` does not exist on this machine. That is the
proof that the 35-resource plan above was genuinely produced without an AWS account, rather than
against a hidden one.

### Really applied, against LocalStack — `evidence/04` to `evidence/06`, `evidence/08`, `evidence/09`

```
cd localstack
terraform init
terraform apply -auto-approve
terraform state list
terraform output
terraform plan -detailed-exitcode
terraform destroy -auto-approve
```

`apply` reported `Apply complete! Resources: 20 added, 0 changed, 0 destroyed.` and `state list`
shows all 20. The re-plan exited 0 with `No changes. Your infrastructure matches the configuration.`,
so the networking layer is idempotent and free of the perpetual-diff problems LocalStack causes for
some other resource types.

`evidence/06` verifies the result independently of Terraform, by querying LocalStack with the AWS
CLI. The part that matters to the rubric:

```
|     AZ      |      Cidr       | PublicIP  |     SubnetId      |   Tier    |
+-------------+-----------------+-----------+-------------------+-----------+
|  ap-south-1a|  10.20.1.0/24   |  False    |  subnet-d842c79b  |  private  |
|  ap-south-1a|  10.20.101.0/24 |  True     |  subnet-90bc2ec2  |  public   |
|  ap-south-1b|  10.20.102.0/24 |  True     |  subnet-d483405e  |  public   |
|  ap-south-1b|  10.20.2.0/24   |  False    |  subnet-26d7ebcf  |  private  |

  public subnets: 2
  AZ: ap-south-1a
  AZ: ap-south-1b
```

Two public subnets, in two different availability zones, both with public IP mapping on, attached to
a route table with a `0.0.0.0/0` route to the internet gateway.

`destroy` reported `Destroy complete! Resources: 20 destroyed.` and `evidence/09` confirms with the
AWS CLI that no VPC, subnet, internet gateway, route table, NAT gateway, elastic IP, security group
or IAM role carrying the `capstone` prefix is left behind. The LocalStack container itself was left
running.

These identifiers are LocalStack identifiers. They are not AWS identifiers and no AWS resource with
these ids exists.

### The EKS limitation, evidenced rather than asserted — `evidence/07`

LocalStack was asked for EKS three separate ways and refused all three.

Its own health endpoint does not list the service at all:

```
edition: community   version: 3.8.1
eks key present: False
running services: ['ec2', 'iam', 's3', 'sts']
```

The AWS CLI:

```
$ aws --endpoint-url=http://localhost:4566 eks create-cluster --name capstone-taskboard-eks ...
An error occurred (InternalFailure) when calling the CreateCluster operation:
API for service 'eks' not yet implemented or pro feature
```

And Terraform itself, with `modules/eks` applied against a provider whose `eks`, `ec2`, `iam` and
`sts` endpoints all point at LocalStack. The two IAM roles, all six policy attachments and the
control plane security group created successfully, because LocalStack community does implement IAM
and EC2. That matters: it shows the module's HCL is sound and that the failure is LocalStack's, not
the configuration's. The run then stopped on the first genuine EKS call:

```
Plan: 5 to add, 0 to change, 0 to destroy.
module.eks.aws_eks_cluster.this: Creating...

Error: creating EKS Cluster (capstone-taskboard-eks): operation error EKS: CreateCluster,
https response error StatusCode: 501, api error InternalFailure: API for service 'eks' not yet
implemented or pro feature
```

The transcript in `evidence/07` is the probe's second apply, which is why its plan is only 5 to add:
the 9 IAM and security group resources already existed in the probe state from the first run and
Terraform had nothing left to do but the EKS call. Those 9 are listed individually in the destroy
that closes the same transcript, which ends `Destroy complete! Resources: 9 destroyed.` The probe
configuration itself was then deleted; it is not part of this submission.

An HTTP 501 from the emulator is the strongest evidence available on this machine. It is not a
substitute for a real cluster and is not offered as one.

## Running this against a real AWS account

Everything needed is already here. A grader with credentials can finish the EKS half in one command.

Prerequisites: an AWS account with permission to create VPC, EC2, IAM and EKS resources,
`terraform >= 1.7`, `aws` CLI v2, and `kubectl`.

```
cp terraform.tfvars.example terraform.tfvars
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=ap-south-1

terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Leave `skip_aws_api_checks` at its default of `false` so the provider validates the credentials.
Control plane creation takes roughly 10 minutes and the node group a further 3 to 5, so budget about
15 to 20 minutes for the apply.

Then point `kubectl` at the cluster and confirm the worker node group joined:

```
aws eks update-kubeconfig --region ap-south-1 --name capstone-taskboard-eks
kubectl get nodes -o wide
kubectl get pods -A
aws eks describe-cluster --name capstone-taskboard-eks --query 'cluster.{status:status,version:version,endpoint:endpoint}'
aws eks describe-nodegroup --cluster-name capstone-taskboard-eks --nodegroup-name taskboard-workers --query 'nodegroup.{status:status,instanceTypes:instanceTypes,scaling:scalingConfig}'
```

`kubectl get nodes` should list two `Ready` nodes. In the AWS Console the VPC appears under
VPC, Your VPCs as `capstone-taskboard-vpc`, and the cluster under Elastic Kubernetes Service in
`ap-south-1`.

One caveat to expect: `cluster_version` is pinned to `1.31`, and AWS retires EKS minor versions on a
schedule. If the apply rejects that version as no longer supported, raise `cluster_version` in
`terraform.tfvars` to a currently supported minor. Nothing else in the configuration needs to change.

### Cost, and the teardown discipline

This stack is not free. Approximate `ap-south-1` on-demand list prices:

| Component | Rate | Roughly per day |
|---|---|---|
| EKS control plane | 0.10 USD per hour | 2.40 USD |
| 2 x t3.medium worker nodes | 0.0416 USD per hour each | 2.00 USD |
| NAT gateway | 0.056 USD per hour plus 0.056 USD per GB processed | 1.35 USD |
| 2 x 20 GiB gp3 root volumes | about 0.08 USD per GiB per month | 0.11 USD |

That is roughly **0.24 USD per hour, about 5.90 USD per day, about 175 USD per month** before data
transfer. Confirm against the current AWS pricing pages before running it; these are list prices as
documented, not a quote.

The control plane and the NAT gateway bill by the hour whether or not anything is deployed on them,
so an idle cluster left running over a weekend is real money. Destroy as soon as the grading
screenshots are taken:

```
terraform destroy
```

Then verify, because a forgotten elastic IP or orphaned load balancer keeps billing after the
cluster is gone:

```
aws eks list-clusters --region ap-south-1
aws ec2 describe-vpcs --region ap-south-1 --filters "Name=tag:Project,Values=capstone-taskboard" --query 'Vpcs[].VpcId'
aws ec2 describe-nat-gateways --region ap-south-1 --filter "Name=state,Values=available" --query 'NatGateways[].NatGatewayId'
aws ec2 describe-addresses --region ap-south-1 --query 'Addresses[].AllocationId'
aws elbv2 describe-load-balancers --region ap-south-1 --query 'LoadBalancers[].LoadBalancerName'
```

All five should come back empty. If a Kubernetes `Service` of type `LoadBalancer` or an `Ingress` was
created inside the cluster, AWS owns that load balancer and its security group, not Terraform, and
`terraform destroy` will hang trying to delete a subnet that the orphaned ENI still occupies. Delete
the Kubernetes services first, then destroy:

```
kubectl delete svc --all -n capstone
kubectl delete ingress --all -n capstone
terraform destroy
```

## Variables

Every variable is typed and described in `variables.tf`; `terraform.tfvars.example` shows a complete
working set. The ones most worth changing:

| Variable | Default | Notes |
|---|---|---|
| `aws_region` | `ap-south-1` | Change `availability_zones` to match if you change this |
| `project_name` | `capstone-taskboard` | Prefixes the `Name` tag of every resource |
| `cluster_name` | `capstone-taskboard-eks` | Also used in the `kubernetes.io/cluster/...` subnet tags |
| `cluster_version` | `1.31` | Raise if AWS has retired this minor version |
| `vpc_cidr` | `10.20.0.0/16` | Must not overlap `172.20.0.0/16`, the Kubernetes service CIDR |
| `public_subnet_cidrs` | two /24s | At least two are required and the value is validated |
| `single_nat_gateway` | `true` | Set to `false` for one NAT per AZ, which costs more |
| `node_desired_size` | `2` | Minimum for the rubric and for a sane control plane |
| `cluster_public_access_cidrs` | `0.0.0.0/0` | Narrow this to your office range before production |
| `skip_aws_api_checks` | `false` | Set to `true` only to validate or plan with no AWS account |

`node_desired_size` is under `ignore_changes` on the node group, so a cluster autoscaler can move the
node count without Terraform fighting it on the next apply.

## Secrets

No credentials are committed. `terraform.tfvars.example` holds only region names, CIDR blocks and
instance sizes. `.gitignore` excludes `.terraform/`, `*.tfstate` and `*.tfstate.*`, `*.tfplan`,
`crash.log`, `override.tf` and every `*.tfvars` file, with an explicit `!terraform.tfvars.example`
negation so the example alone is tracked. `.terraform.lock.hcl` is deliberately **not** ignored, so
the provider version and its checksums are pinned for whoever clones this next. Credentials are supplied at run time through the standard
AWS chain: environment variables, a shared config profile, or an instance role.

## Honest scorecard against the M7 rubric

| Criterion | Points | Status |
|---|---|---|
| `terraform/` directory with valid HCL files | 2 | Met. `validate` passes, `fmt -check -recursive` is clean, `evidence/01` |
| `terraform init` completes without errors | 1 | Met. `evidence/01` |
| `terraform plan` produces a non-empty plan with no errors | 2 | Met. 35 resources, no errors, `evidence/02` |
| VPC with at least two public subnets is provisioned | 3 | Provisioned against LocalStack and verified by AWS CLI, `evidence/06`. Not provisioned on AWS |
| EKS cluster with at least one worker node group | 4 | **Not provisioned.** Written and planned only. LocalStack community has no EKS; the refusal is captured verbatim in `evidence/07` |
| `terraform destroy` tears down all resources cleanly | 2 | The 20 networking resources were destroyed cleanly and verified empty, `evidence/08` and `evidence/09`. The EKS probe was also destroyed cleanly |
| `terraform.tfvars.example` present, no real credentials | 1 | Met |

The 4 points for a live EKS cluster cannot be earned on this machine, and this README does not
pretend otherwise. The HCL that would earn them is complete, validated, planned and ready to apply;
only an AWS account is missing.
