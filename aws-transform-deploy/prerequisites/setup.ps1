<#
setup.ps1

.SYNOPSIS
    Sets up IAM roles and optionally an S3 bucket for AWS Transform deployment.

.PARAMETER KmsKeyArn
    Optional KMS Key ARN for encryption/decryption.

.PARAMETER StackName
    Optional CloudFormation stack name. Default: AWSTransform-Deploy-IAM-Role-Stack

.PARAMETER DisableBucketCreation
    Whether to create the S3 bucket required for AWS Transform to store build artifacts in deployment.

.EXAMPLE
    .\setup.ps1 -StackName "MyStack" -DisableBucketCreation -KmsKeyArn "arn:aws:kms:..."
#>

param (
	[string]$KmsKeyArn = "",
	[string]$StackName = "AWSTransform-Deploy-IAM-Role-Stack",
	[switch]$DisableBucketCreation,
	[switch]$Help
)

$TemplateFile = "iam_roles.yml"

function Log {
	param(
		[Parameter(Mandatory=$true)]
		[string]$Message,
		[ValidateSet('INFO','WARN','ERROR','SUCCESS','DEBUG','AWS CLI')]
		[string]$Severity = 'INFO'
	)

	$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	Write-Host "[$timestamp] [$Severity] $Message"
}

function Prefix-Output {
	param (
		[string]$Severity = "AWS CLI"
	)
	process {
		if ($_ -ne "") {
			Log $_ $Severity
		}
	}
}

function Show-Usage {
	Log "Usage: ./setup.ps1 [-StackName <StackName>] [-DisableBucketCreation] [-KmsKeyArn <ARN>] [-Help]"
	exit 0
}

if ($Help) {
	Show-Usage
}

if (-not (Get-Command "aws" -ErrorAction SilentlyContinue)) {
	Log "AWS CLI is not installed or not in PATH. Please install it first." "ERROR"
	exit 1
}

Log "Stack Name: $StackName"
Log "Bucket Creation: $(-not $DisableBucketCreation)"
Log "KMS Key ARN: $(if ($KmsKeyArn) { $KmsKeyArn } else { '<none>' })"

if ($DisableBucketCreation) {
	Log "Bucket creation is disabled. An S3 bucket is required for AWS Transform deployment." "WARN"
}

Write-Host ""
Log "=== Checking ECS Service-Linked Role ==="

$output = aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com 2>&1

if ($LASTEXITCODE -ne 0) {
	if ($output -match "Service role name .* has been taken") {
		Log "ECS service-linked role already exists."
	} else {
		Log "Failed to create service-linked role." "ERROR"
		$output | ForEach-Object { $_ | Prefix-Output }
		exit 1
	}
} else {
	Log "Service-linked role created successfully."
}

Write-Host ""
Log "=== Deploying CloudFormation Stack ==="

$bucketFlag = if ($DisableBucketCreation) { "false" } else { "true" }
$paramOverrides = "CreateS3Bucket=$bucketFlag"
if ($KmsKeyArn) {
	$paramOverrides += " KmsKeyArn=$KmsKeyArn"
}

aws cloudformation deploy `
    --template-file $TemplateFile `
    --stack-name $StackName `
    --capabilities CAPABILITY_NAMED_IAM `
    --parameter-overrides $paramOverrides `
    --tags CreatedFor=AWSTransform 2>&1 |
		ForEach-Object { $_ | Prefix-Output }

if ($LASTEXITCODE -ne 0) {
	Log "CloudFormation deployment failed with exit code $LASTEXITCODE." "ERROR"
	exit 1
}

Write-Host ""
Log "=== Deployment Complete ==="

Log "Next steps:"
Log "- Return to the AWS Transform website and select 'Continue' to configure application infrastructure if not done yet."
Log "- Once infrastructure is configured, deploy your application by selecting the 'Deploy' button in the AWS Transform website."
Log "- Alternatively, consult the README located in the 'aws-transform-deploy' folder of your project’s parent directory"
Log "  if you prefer self-managed deployment or no further configuration is needed."
Log "- Optionally, review and update IAM role permissions if your application requires further customization."