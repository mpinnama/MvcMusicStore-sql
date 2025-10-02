# Copyright 2025 Amazon.com, Inc. or its affiliates. All Rights Reserved.

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("ec2", "ecs")]
    [string]$DeploymentType,

    [string]$StackName,
    [string]$Region,
    [switch]$SkipAssumeRole,

    # EC2-specific parameters
    [Parameter(ParameterSetName="EC2")]
    [string]$SubnetId,
    [Parameter(ParameterSetName="EC2")]
    [string[]]$SecurityGroupIds,
    [Parameter(ParameterSetName="EC2")]
    [string]$EC2InstanceProfile,
    [Parameter(ParameterSetName="EC2")]
    [string]$InstanceType,
    [Parameter(ParameterSetName="EC2")]
    [string]$CustomAmiId,
    [Parameter(ParameterSetName="EC2")]
    [int]$VolumeSize,
    [Parameter(ParameterSetName="EC2")]
    [string]$MainBinary,

    # ECS-specific parameters
    [Parameter(ParameterSetName="ECS")]
    [string]$ResourcePrefix,
    [Parameter(ParameterSetName="ECS")]
    [string]$VpcId = "",
    [Parameter(ParameterSetName="ECS")]
    [string]$PublicSubnetIds = "",
    [Parameter(ParameterSetName="ECS")]
    [string]$PrivateSubnetIds = "",
    [Parameter(ParameterSetName="ECS")]
    [string]$AlbArn = "",
    [Parameter(ParameterSetName="ECS")]
    [string]$AlbSecurityGroupId = "",
    [Parameter(ParameterSetName="ECS")]
    [string]$EcsClusterName = "",
    [Parameter(ParameterSetName="ECS")]
    [string]$EcsSecurityGroupId = "",
    [Parameter(ParameterSetName="ECS")]
    [string]$CertificateArn = "",
    [Parameter(ParameterSetName="ECS")]
    [int]$AlbListenerPort = 0
)

$TemplateFilePath = if ($DeploymentType -eq "ec2") { "iac_template.yml" } else { "ecs_infra_template.yml" }
$InstanceIdFile = "instance_id_from_infra_deployment.config"
$gitignorePath = ".gitignore"

# Defaults
$defaults = @{
    # EC2 defaults
    InstanceType = "t3.small"
    VolumeSize = "30"
    Region = "us-east-1"
    SubnetId = "subnet-0c0dbb9127356b2f1"
    SecurityGroupIds = "['sg-07df1fdfb2255b944', 'sg-063c4a2619bb57903']"
    EC2InstanceProfile = "AWSTransform-Deploy-App-Instance-Role"
    CustomAmiId = ""
    MainBinary = "MvcMusicStore"

    # ECS defaults
    ResourcePrefix = ""
    VpcId = ""
    PublicSubnetIds = ""
    PrivateSubnetIds = ""
    AlbArn = ""
    AlbSecurityGroupId = ""
    EcsClusterName = ""
    EcsSecurityGroupId = ""
    CertificateArn = ""
    AlbListenerPort = ""
}

function Initialize-Parameters {
    param(
        [string]$DeploymentType,
        [string]$StackName,
        [string]$Region,
        [switch]$SkipAssumeRole,
        [hashtable]$Params
    )

    # Set defaults based on deployment type
    if ($DeploymentType -eq "ec2") {
        # EC2 parameter defaults
        if (-not $InstanceType) { $InstanceType = $defaults.InstanceType }
        if (-not $VolumeSize) { $VolumeSize = $defaults.VolumeSize }
        if (-not $Region) { $Region = $defaults.Region }
        if (-not $SubnetId) { $SubnetId = $defaults.SubnetId }
        if (-not $SecurityGroupIds) { 
            if ($defaults.SecurityGroupIds) {
                $SecurityGroupIds = $defaults.SecurityGroupIds -split '[,\s]+'
            } else {
                $SecurityGroupIds = @()
            }
        }
        if (-not $EC2InstanceProfile) { $EC2InstanceProfile = $defaults.EC2InstanceProfile }
        if (-not $CustomAmiId) { $CustomAmiId = $defaults.CustomAmiId }
        if (-not $MainBinary) { $MainBinary = $defaults.MainBinary }
    }
    else {
        # ECS parameter defaults
        if (-not $Region) { $Region = $defaults.Region }
        if (-not $ResourcePrefix) { $ResourcePrefix = $defaults.ResourcePrefix }
        if (-not $VpcId) { $VpcId = $defaults.VpcId }
        if (-not $PublicSubnetIds) { 
            if ($defaults.PublicSubnetIds) {
                $PublicSubnetIds = $defaults.PublicSubnetIds -split '[,\s]+'
            } else {
                $PublicSubnetIds = ""
            }
        }
        if (-not $PrivateSubnetIds) { 
            if ($defaults.PrivateSubnetIds) {
                $PrivateSubnetIds = $defaults.PrivateSubnetIds -split '[,\s]+'
            } else {
                $PrivateSubnetIds = ""
            }
        }
        if (-not $AlbArn) { $AlbArn = $defaults.AlbArn }
        if (-not $AlbSecurityGroupId) { $AlbSecurityGroupId = $defaults.AlbSecurityGroupId }
        if (-not $EcsClusterName) { $EcsClusterName = $defaults.EcsClusterName }
        if (-not $EcsSecurityGroupId) { $EcsSecurityGroupId = $defaults.EcsSecurityGroupId }
        if (-not $CertificateArn) { $CertificateArn = $defaults.CertificateArn }
        if (-not $AlbListenerPort) { $AlbListenerPort = $defaults.AlbListenerPort }
    }

    # Return the appropriate parameter set based on deployment type
    if ($DeploymentType -eq "ec2") {
        return @{
            DeploymentType = $DeploymentType
            StackName = $StackName
            Region = $Region
            InstanceType = $InstanceType
            VolumeSize = $VolumeSize
            SubnetId = $SubnetId
            SecurityGroupIds = $SecurityGroupIds
            EC2InstanceProfile = $EC2InstanceProfile
            CustomAmiId = $CustomAmiId
            MainBinary = $MainBinary
        }
    }
    else {
        return @{
            DeploymentType = $DeploymentType
            StackName = $StackName
            Region = $Region
            ResourcePrefix = $ResourcePrefix
            VpcId = $VpcId
            PublicSubnetIds = $PublicSubnetIds
            PrivateSubnetIds = $PrivateSubnetIds
            AlbArn = $AlbArn
            AlbSecurityGroupId = $AlbSecurityGroupId
            EcsClusterName = $EcsClusterName
            EcsSecurityGroupId = $EcsSecurityGroupId
            CertificateArn = $CertificateArn
            AlbListenerPort = $AlbListenerPort
        }
    }
}

function Get-CommonErrorSolution {
    param (
        [string]$errorMessage
    )
    
    $solutions = @{
        "role cannot be assumed"  = "Check IAM role permissions and trust relationships"
        "subnet"                  = "Verify subnet ID exists and is in the correct VPC"
        "security group"          = "Verify security group IDs exist and are in the correct VPC"
        "instance profile"        = "Verify instance profile exists and has correct permissions"
        "parameter validation"    = "Check if all parameter values meet the template constraints"
        "VPC"                     = "Verify VPC ID exists and is in the correct region"
        "ECS cluster"             = "Verify ECS cluster name is correct and the cluster exists"
        "certificate"             = "Ensure the ACM certificate ARN is valid and in the correct region"
    }

    foreach ($key in $solutions.Keys) {
        if ($errorMessage -match $key) {
            return $solutions[$key]
        }
    }
    
    return "Review CloudFormation documentation and check AWS Console for more details"
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','DEBUG')]
        [string]$Severity = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Severity] $Message" 
}

function Show-Usage {
    Write-Log @"
Usage: 
    .\deploy-stack.ps1 -DeploymentType <ec2|ecs> [options]

Common Parameters:
    -DeploymentType        : (Required) Type of deployment (ec2 or ecs)
    -StackName             : (Optional) Name for the CloudFormation stack
    -Region                : (Optional) AWS region for deployment. Default: $($defaults.Region)
    -SkipAssumeRole        : (Optional) Skip assuming the deployment role

EC2-specific Parameters:
    -SubnetId              : (Required) ID of the VPC subnet for EC2 instance
    -SecurityGroupIds      : (Required) Comma-separated list of security group IDs
    -EC2InstanceProfile    : (Required) IAM instance profile name for EC2
    -InstanceType          : (Optional) EC2 instance type. Default: $($defaults.InstanceType)
    -CustomAmiId           : (Optional) Custom Amazon Machine Image ID
    -VolumeSize            : (Optional) Size in GB for the EC2 instance root volume. Default: $($defaults.VolumeSize)
    -MainBinary            : (Required) Name of the main executable binary

ECS-specific Parameters:
    -ResourcePrefix        : (Required) Prefix for resource names
    -VpcId                 : (Optional) ID of the VPC for ECS deployment
    -PublicSubnetIds       : (Optional) Comma-separated list of public subnet IDs
    -PrivateSubnetIds      : (Optional) Comma-separated list of private subnet IDs
    -AlbArn                : (Optional) ARN of existing Application Load Balancer
    -AlbSecurityGroupId    : (Optional) ID of existing ALB security group
    -EcsClusterName        : (Optional) Name of existinting ECS cluster
    -EcsSecurityGroupId    : (Optional) ID of existing ECS security group
    -CertificateArn        : (Optional) ARN of ACM certificate for HTTPS listener
    -AlbListenerPort       : (Optional) Port for ALB listener. Default: 80 (HTTP) or 443 (HTTPS)

This script will:    
    Validate all input parameters
    Deploy the stack and wait for completion
    Write the infrastructure details to file '$InstanceIdFile'
    Provide detailed error information and suggestions if deployment fails
    Show successful completion message if deployment succeeds
"@ -Severity 'INFO'
}

function Write-ErrorDetails {
    param (
        [string]$StackName
    )
    
    $stackEvents = Get-CFNStackEvent -StackName $StackName | Where-Object { $_.ResourceStatus -like "*FAILED" }
    if ($stackEvents) {
        Write-Log "Error Details:" -Severity 'ERROR'
        foreach ($event in $stackEvents) {
            Write-Log "Resource: $($event.LogicalResourceId)" -Severity 'WARN'
            Write-Log "Status: $($event.ResourceStatus)" -Severity 'ERROR'
            Write-Log "Reason: $($event.ResourceStatusReason)" -Severity 'ERROR'
            Write-Log "-------------------" -Severity 'INFO'
        }
    }
}

function Install-RequiredModules {
    $requiredModules = @(
        "AWS.Tools.Common",
        "AWS.Tools.CloudFormation",
        "AWS.Tools.SimpleSystemsManagement",
        "AWS.Tools.SecurityToken"
    )

    $missingModules = @()
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            $missingModules += $module
        }
    }

    if ($missingModules.Count -gt 0) {
        Write-Log "The following AWS PowerShell modules are not installed:" -Severity 'ERROR'
        foreach ($module in $missingModules) {
            Write-Log "- $module" -Severity 'ERROR'
        }
        Write-Log "Please install the missing modules by running:" -Severity 'ERROR'
        foreach ($module in $missingModules) {
            Write-Log "Install-Module -Name $module -Force" -Severity 'ERROR'
        }
        exit 1
    }
}

function Add-FileToGitignore {
    param(
        [string]$FileToIgnore
    )
    
    if (Test-Path $gitignorePath) {
        $gitignoreContent = Get-Content $gitignorePath
        if ($gitignoreContent -notcontains $FileToIgnore) {
            Add-Content $gitignorePath "`n$FileToIgnore"
        }
    } else {
        $FileToIgnore | Out-File $gitignorePath
    }
}

function Assume-DeploymentRole {
    $RoleArn = "arn:aws:iam::$((Get-STSCallerIdentity).Account):role/${ResourcePrefix}-Deployment-Role"
    Write-Log "Assuming role: $RoleArn" -Severity 'INFO'
    try {
        $Credentials = (Use-STSRole -RoleArn $RoleArn -RoleSessionName "DeploymentSession").Credentials
        Set-AWSCredential -AccessKey $Credentials.AccessKeyId -SecretKey $Credentials.SecretAccessKey -SessionToken $Credentials.SessionToken -Scope Global
    }
    catch {
        Write-Log "Failed to assume role. Please verify that:" -Severity 'ERROR'
        Write-Log "1. The role exists in your account" -Severity 'ERROR'
        Write-Log "2. Your IAM user/role has permission to assume this role" -Severity 'ERROR'
        Write-Log "3. The role trust policy allows your IAM user/role to assume it" -Severity 'ERROR'
        Write-Log "Error details: $_" -Severity 'ERROR'
        exit 1
    }
}

function Main {
    Install-RequiredModules

    $params = Initialize-Parameters -DeploymentType $DeploymentType `
                                    -StackName $StackName `
                                    -Region $Region `
                                    -SkipAssumeRole:$SkipAssumeRole `
                                    -Params $PSBoundParameters

    $StackName = $params.StackName
    $Region = $params.Region
    $DeploymentType = $params.DeploymentType

    try {
        $cfnParams = @()
        if ($DeploymentType -eq "ec2") {
            $cfnParams = @(
                @{ ParameterKey="SubnetId"; ParameterValue=$SubnetId }
                @{ ParameterKey="ApplicationName"; ParameterValue=$MainBinary }
                @{ ParameterKey="InstanceType"; ParameterValue=$InstanceType }
                @{ ParameterKey="CustomAmiId"; ParameterValue=$CustomAmiId }
                @{ ParameterKey="VolumeSize"; ParameterValue=$VolumeSize.ToString() }
                @{ ParameterKey="EC2InstanceProfile"; ParameterValue=$EC2InstanceProfile }
                @{ ParameterKey="SecurityGroupIds"; ParameterValue=($SecurityGroupIds -join ',') }
            )
        } else {
            $cfnParams = @(
                @{ ParameterKey="ResourcePrefix"; ParameterValue=$ResourcePrefix }
                @{ ParameterKey="VpcId"; ParameterValue=$VpcId }
                @{ ParameterKey="PublicSubnetIds"; ParameterValue=$PublicSubnetIds }
                @{ ParameterKey="PrivateSubnetIds"; ParameterValue=$PrivateSubnetIds }
                @{ ParameterKey="AlbArn"; ParameterValue=$AlbArn }
                @{ ParameterKey="AlbSecurityGroupId"; ParameterValue=$AlbSecurityGroupId }
                @{ ParameterKey="EcsClusterName"; ParameterValue=$EcsClusterName }
                @{ ParameterKey="EcsSecurityGroupId"; ParameterValue=$EcsSecurityGroupId }
                @{ ParameterKey="CertificateArn"; ParameterValue=$CertificateArn }
                @{ ParameterKey="AlbListenerPort"; ParameterValue=$AlbListenerPort.ToString() }
            )
        }

        try {
            $existingStack = Get-CFNStack -StackName $StackName -ErrorAction Stop
        }
        catch {
            $existingStack = $null
        }
        
        if ($existingStack) {
            Write-Log "Stack $StackName already exists." -Severity 'WARN'
            try {
                $outputs = (Get-CFNStack -StackName $StackName).Outputs
                if ($DeploymentType -eq "ec2") {
                    $instanceId = ($outputs | Where-Object { $_.OutputKey -eq "InstanceId" }).OutputValue
                    $publicIp = ($outputs | Where-Object { $_.OutputKey -eq "PublicIp" }).OutputValue
                    
                    if ($instanceId -and $publicIp) {
                        Write-Log "Current stack has:" -Severity 'INFO'
                        Write-Log "Instance ID: $instanceId" -Severity 'INFO'
                        Write-Log "Public IP: $publicIp" -Severity 'INFO'
                    } else {
                        Write-Log "Warning: This stack doesn't appear to be created for EC2 infrastructure (missing instance details)" -Severity 'WARN'
                    }
                } else {
                    $clusterName = ($outputs | Where-Object { $_.OutputKey -eq "EcsClusterName" }).OutputValue
                    $vpcId = ($outputs | Where-Object { $_.OutputKey -eq "VpcId" }).OutputValue
                    $albArn = ($outputs | Where-Object { $_.OutputKey -eq "AlbArn" }).OutputValue
                    
                    if ($clusterName -and $vpcId -and $albArn) {
                        Write-Log "Current stack has:" -Severity 'INFO'
                        Write-Log "ECS Cluster Name: $clusterName" -Severity 'INFO'
                        Write-Log "VPC ID: $vpcId" -Severity 'INFO'
                        Write-Log "ALB ARN: $albArn" -Severity 'INFO'
                    } else {
                        Write-Log "Warning: This stack doesn't appear to be created for ECS infrastructure (missing cluster details)" -Severity 'WARN'
                    }
                }
            } catch {
                Write-Log "Warning: Unable to get details from existing stack" -Severity 'WARN'
            }
            $confirmation = Read-Host "Are you sure you want to delete the existing stack? (y/n)"
            if ($confirmation -ne 'y') {
                Write-Log "Stack deletion cancelled by user" -Severity 'INFO'
                exit 0
            }
            Write-Log "Deleting stack $StackName..." -Severity 'WARN'
            Remove-CFNStack -StackName $StackName -Force
            Write-Log "Waiting for stack deletion to complete..." -Severity 'WARN'
            try {
                Wait-CFNStack -StackName $StackName
                Write-Log "Stack deletion completed" -Severity 'SUCCESS'
            }
            catch {
                if ($_.Exception.Message -like "*Stack*does not exist*") {
                    Write-Log "Stack deletion completed" -Severity 'SUCCESS'
                }
                else {
                    throw
                }
            }
        }

        Write-Log "Deploying stack: $StackName" -Severity 'SUCCESS'

        New-CFNStack -StackName $StackName `
                     -TemplateBody (Get-Content $TemplateFilePath -Raw) `
                     -Parameter $cfnParams `
                     -Capability CAPABILITY_IAM `
                     -Tag @{Key="CreatedFor"; Value="AWSTransformDotNET"}

        Write-Log "Waiting for stack deployment to complete..." -Severity 'WARN'
        $lastEvent = $null
        $timeout = New-TimeSpan -Minutes 10
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        while ($true) {
            if ($stopwatch.Elapsed -gt $timeout) {
                Write-Log "Deployment timed out after 10 minutes" -Severity 'ERROR'
                exit 1            
            }
            
            $status = (Get-CFNStack -StackName $StackName).StackStatus
            $events = Get-CFNStackEvent -StackName $StackName | Select-Object -First 10
            
            [array]::Reverse($events)
            foreach ($event in $events) {
                $eventKey = "$($event.LogicalResourceId) - $($event.ResourceStatus)"
                if ($lastEvent -ne $eventKey) {
                    Write-Log "Current status: $status - Latest event: $($event.LogicalResourceId) - $($event.ResourceStatus) - $($event.ResourceStatusReason)" -Severity 'INFO'
                    $lastEvent = $eventKey
                }
            }
            
            if ($status -match '(COMPLETE|FAILED|ROLLBACK)') {
                break
            }
            Start-Sleep -Seconds 5
        }
        $finalStatus = (Get-CFNStack -StackName $StackName).StackStatus

        if ($finalStatus -eq 'CREATE_COMPLETE') {
            Write-Log "Stack deployment completed successfully!" -Severity 'SUCCESS'
            
            $outputs = (Get-CFNStack -StackName $StackName).Outputs
            if ($outputs) {
                Write-Log "===================" -Severity 'INFO'
                foreach ($output in $outputs) {
                    Write-Log "$($output.OutputKey): $($output.OutputValue)" -Severity 'INFO'
                }
                Write-Log "===================" -Severity 'INFO'
                
                $outputsToSave = @{}
                foreach ($output in $outputs) {
                    $outputsToSave[$output.OutputKey] = $output.OutputValue
                }
                $outputsToSave | ConvertTo-Json | Out-File $InstanceIdFile
                Write-Log "Infrastructure details written to $InstanceIdFile" -Severity 'INFO'
                Add-FileToGitignore -FileToIgnore $InstanceIdFile
            }
            Write-Log "Please refer to README.md and deploy.ps1 in order to deploy the application to this infrastructure." -Severity 'INFO'
        }
        else {
            Write-Log "Stack deployment failed with status: $finalStatus" -Severity 'ERROR'
            Write-ErrorDetails -StackName $StackName
            
            $lastError = Get-CFNStackEvent -StackName $StackName | 
                        Where-Object { $_.ResourceStatus -like "*FAILED" -or 
                                     $_.ResourceStatus -eq "ROLLBACK_STARTED" -or 
                                     $_.ResourceStatus -eq "ROLLBACK_IN_PROGRESS" } |
                        Select-Object -First 1
           
            if ($lastError) {
                $errormsg = $lastError.ResourceStatusReason
                Write-Log "Detected error: $errormsg" -Severity 'WARN'
                $suggestion = Get-CommonErrorSolution -errorMessage $errormsg
                Write-Log "Suggested solution: $suggestion" -Severity 'WARN'
            }
            exit 1
        }
    }
    catch {
        Write-Log "An error occurred: $_" -Severity 'ERROR'
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Severity 'ERROR'
        exit 1
    }
    exit 0
}

# Start Script execution
Main