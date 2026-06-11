# Cookbook: Olympus runner on AWS (EC2)

Run the runner on an EC2 instance — good if your org already lives in AWS, your
model gateway is in a VPC, or you want spot/auto-stop cost controls.

> Prereq concepts + the shared **Steps A–D** (bootstrap, register runner,
> secrets, smoke test) live in [`./README.md`](./README.md). This page only
> covers **getting the instance**.

## 1. Launch the instance

### Find a current Ubuntu 24.04 AMI (Canonical publishes it via SSM)

```bash
AMI=$(aws ssm get-parameter \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query 'Parameter.Value' --output text)
echo "$AMI"
```

### Run it

```bash
aws ec2 run-instances \
  --image-id "$AMI" \
  --instance-type t3.medium \
  --key-name <your-keypair> \
  --security-group-ids <sg-id> \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3}' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=olympus-runner}]'

# get the public IP (or use SSM Session Manager and skip SSH/inbound entirely)
aws ec2 describe-instances --filters Name=tag:Name,Values=olympus-runner \
  --query 'Reservations[].Instances[].PublicIpAddress' --output text
ssh ubuntu@<PUBLIC_IP>
```

### Security group

- **Outbound**: 443 (GitHub + your model endpoint). That's all the runner needs.
- **Inbound**: nothing required. For setup, either allow 22 from *your* IP, or —
  better — use **SSM Session Manager** (attach an instance profile with
  `AmazonSSMManagedInstanceCore`) and open no inbound ports at all.

## 2. Sizing & cost (rough, on-demand, us-east-1)

| Instance | vCPU / RAM | ~ / month (24×7) | Good for |
|---|---|---|---|
| `t3.medium` | 2 / 4 GB | ~$30 | triage + review |
| `t3.xlarge` | 4 / 16 GB | ~$120 | + implement with a heavy build |

Cost controls:

- **Stop when idle** — you only pay for the EBS volume while stopped. A simple
  EventBridge schedule + Lambda (or `aws ec2 stop-instances` from cron elsewhere)
  can park it overnight.
- **Spot** — for non-urgent loops, a spot instance cuts ~70%. Add `--instance-market-options`
  and tolerate occasional interruption (the runner re-registers on next boot if
  you bake the setup into user-data or an AMI).

## 3. (optional) Bake it with user-data

Put **Step A** (bootstrap) into the instance **user-data** so a fresh instance
comes up ready; keep the runner **registration** (Step B) separate since the
token is short-lived — or store a re-registration script that fetches a token at
boot via an instance role with GitHub App credentials.

## 4. Bring it online

Continue with **Steps A–D** in [`./README.md`](./README.md): bootstrap the
instance, register the runner (label `self-hosted,olympus`), set the secrets,
smoke-test.

## Pros / cons

| 👍 | 👎 |
|---|---|
| VPC-native (reach a private gateway via subnet/PrivateLink); spot + auto-stop cost controls; SSM = zero inbound | More moving parts (AMI, SG, IAM); priciest of the three at 24×7 on-demand unless you stop/spot it |
