# AWS Transform Deployment – Prerequisite Setup Instructions

This guide covers the initial setup of IAM roles and related AWS resources needed for AWS Transform Deployment.

---

### Prerequisites
1. Admin-level AWS permissions for IAM roles, IAM Instance Profiles, and CloudFormation stacks.
2. AWS CLI installed and configured with appropriate credentials. See the [AWS CLI Auth Setup Guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html) for details.

---

### Using the Bash Setup Script (setup.sh)

```shell
./setup.sh --stack-name MyStack --kms-key-arn arn:aws:kms:... --disable-bucket-creation false
```

**Optional Parameters:**

* `--stack-name`: CloudFormation stack name (default: `AWSTransform-Deploy-IAM-Role-Stack`).

* `--kms-key-arn`: KMS Key ARN for encryption.

* `--disable-bucket-creation`: Whether to create an S3 bucket to store build artifacts (`true` or `false`, default: `false`).

---

### Using the PowerShell Setup Script (setup.ps1)
```powershell
.\setup.ps1 -StackName "MyStack" -KmsKeyArn "arn:aws:kms:..." [-DisableBucketCreation]
```

**Optional Parameters:**

* `-StackName`: CloudFormation stack name (default: `AWSTransform-Deploy-IAM-Role-Stack`).

* `-KmsKeyArn`: KMS Key ARN for encryption.

* `-DisableBucketCreation`: Switch to prevent S3 bucket creation (default is to create the bucket).

---