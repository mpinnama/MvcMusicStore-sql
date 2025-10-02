# Copyright 2025 Amazon.com, Inc. or its affiliates. All Rights Reserved.

param(
    [string]$SubnetId,
    [string[]]$SecurityGroupIds,
    [string]$EC2InstanceProfile, 
    [string]$InstanceType,
    [string]$CustomAmiId,
    [int]$VolumeSize,
    [string]$StackName,
    [string]$Region,
    [string]$MainBinary,
    [switch]$SkipAssumeRole
)

$TemplateFilePath = "iac_template.yml"
$InstanceIdFile = "instance_id_from_infra_deployment.config"
$gitignorePath = ".gitignore"

# Defaults
$defaults = @{
    InstanceType = "t3.small"
    VolumeSize = "30"
    Region = "us-east-1"
    SubnetId = "subnet-0c0dbb9127356b2f1"
    SecurityGroupIds = "['sg-07df1fdfb2255b944', 'sg-063c4a2619bb57903']"
    EC2InstanceProfile = "AWSTransform-Deploy-App-Instance-Role"
    CustomAmiId = ""
    MainBinary = "MvcMusicStore"
}

function Initialize-Parameters {
    param(
        [string]$StackName,
        [string]$SubnetId,
        [string]$EC2InstanceProfile,
        [string[]]$SecurityGroupIds,
        [string]$InstanceType,
        [string]$CustomAmiId,
        [int]$VolumeSize,
        [string]$Region,
        [string]$MainBinary,
        [switch]$SkipAssumeRole
    )

    # Set parameters to defaults if not provided
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

    # Generate stack name if not provided
    if (-not $StackName) {
        $StackName = "$MainBinary-stack" -replace '[^a-zA-Z0-9\-]','-' -replace '\-+','-'
    }

    # Collect missing required parameters
    $missingParams = @()

    foreach ($param in @{
        SubnetId = $SubnetId 
        EC2InstanceProfile = $EC2InstanceProfile
        SecurityGroupIds = $SecurityGroupIds
    }.GetEnumerator()) {
        if ( -not $param.Value) {
            $missingParams += $param.Key
        }
    }

    # If any required parameters are missing, show error and usage
    if ($missingParams.Count -gt 0) {
        Write-Log "Missing required parameters: $($missingParams -join ', ')" -Severity 'ERROR'
        Show-Usage
        exit 1
    }

    # Set AWS region
    Set-DefaultAWSRegion -Region $Region

    # Assume role if not skipped
    if (-not $SkipAssumeRole) {
        try {
            $roleArn = "arn:aws:iam::$((Get-STSCallerIdentity).Account):role/AWSTransformDotNET-Infra-Deployment-Role"
            Write-Log "Assuming role: $roleArn" -Severity 'INFO'
            $credentials = (Use-STSRole -RoleArn $roleArn -RoleSessionName "DeploymentSession").Credentials
            Set-AWSCredential -AccessKey $credentials.AccessKeyId -SecretKey $credentials.SecretAccessKey -SessionToken $credentials.SessionToken -Scope Global
        }
        catch {
            Write-Log "Failed to assume role. Please verify that:" -Severity 'ERROR'
            Write-Log "1. The role 'AWSTransformDotNET-Infra-Deployment-Role' exists in your account" -Severity 'ERROR'
            Write-Log "2. Your IAM user/role has permission to assume this role" -Severity 'ERROR'
            Write-Log "3. The role trust policy allows your IAM user/role to assume it" -Severity 'ERROR'
            Write-Log "Error details: $_" -Severity 'ERROR'
            exit 1
        }
    }

    return @{
        StackName = $StackName
        SubnetId = $SubnetId
        EC2InstanceProfile = $EC2InstanceProfile
        SecurityGroupIds = $SecurityGroupIds
        InstanceType = $InstanceType
        CustomAmiId = $CustomAmiId
        VolumeSize = $VolumeSize
        Region = $Region
        MainBinary = $MainBinary
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
    .\deploy-stack.ps1 -SubnetId <subnet-id> `
                       -SecurityGroupIds <security-group-id1>,<security-group-id2>... `
                       -EC2InstanceProfile <instance-profile> `
                       -InstanceType <instance-type> `
                       -CustomAmiId <ami-id> `
                       -VolumeSize <volume-size-gb> `
                       -StackName <stack-name> `
                       -Region <region> `
                       -SkipAssumeRole

Parameters:
    -SubnetId                 : (Required) ID of the VPC subnet where resources will be provisioned
    -SecurityGroupIds : (Required) Comma-separated list of security group IDs for network access control (e.g. sg1 or sg1,sg2)
    -EC2InstanceProfile       : (Required) IAM instance profile name for EC2 instance permissions. Default: '$($defaults.EC2InstanceProfile)'.
    -InstanceType            : (Optional) EC2 instance type that defines CPU, memory and networking capacity. Default: t3.small
    -CustomAmiId             : (Optional) Custom Amazon Machine Image ID for EC2 instance operating system and configuration. Default: None
    -VolumeSize             : (Optional) Size in GB for the EC2 instance root EBS volume. Default: 30 GB
    -StackName              : (Optional) Unique identifier for the CloudFormation stack. Default: $($defaults.MainBinary)-stack
    -Region                 : (Optional) AWS region where resources will be deployed. Default: $($defaults.Region)
    -SkipAssumeRole         : (Optional) Skip assuming the AWSTransformDotNET-Infra-Deployment-Role. Default: False

This script will:    
    Validate all input parameters
    Deploy the stack and wait for completion
    Write the instance ID to file '$InstanceIdFile' to be used by the consecutive usage of application deployment script
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

function Main {
    Install-RequiredModules

    $params = Initialize-Parameters -StackName $StackName `
                                        -SubnetId $SubnetId `
                                        -EC2InstanceProfile $EC2InstanceProfile `
                                        -SecurityGroupIds $SecurityGroupIds `
                                        -MainBinary $MainBinary `
                                        -InstanceType $InstanceType `
                                        -CustomAmiId $CustomAmiId `
                                        -VolumeSize $VolumeSize `
                                        -Region $Region

    $StackName = $params.StackName
    $SubnetId = $params.SubnetId
    $EC2InstanceProfile = $params.EC2InstanceProfile
    $SecurityGroupIds = $params.SecurityGroupIds
    $InstanceType = $params.InstanceType
    $CustomAmiId = $params.CustomAmiId
    $VolumeSize = $params.VolumeSize
    $Region = $params.Region
    $MainBinary = $params.MainBinary

    try {
        $securityGroupsString = $SecurityGroupIds -join ','

        $cfnParams = @(
            @{ ParameterKey="SubnetId"; ParameterValue=$SubnetId }
            @{ ParameterKey="ApplicationName"; ParameterValue=$MainBinary }
            @{ ParameterKey="InstanceType"; ParameterValue=$InstanceType }
            @{ ParameterKey="CustomAmiId"; ParameterValue=$CustomAmiId }
            @{ ParameterKey="VolumeSize"; ParameterValue=$VolumeSize.ToString() }
            @{ ParameterKey="EC2InstanceProfile"; ParameterValue=$EC2InstanceProfile }
            @{ ParameterKey="SecurityGroupIds"; ParameterValue=$securityGroupsString }
        )


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
                $instanceId = ($outputs | Where-Object { $_.OutputKey -eq "InstanceId" }).OutputValue
                $publicIp = ($outputs | Where-Object { $_.OutputKey -eq "PublicIp" }).OutputValue
                
                if ($instanceId -and $publicIp) {
                    Write-Log "Current stack has:" -Severity 'INFO'
                    Write-Log "Instance ID: $instanceId" -Severity 'INFO'
                    Write-Log "Public IP: $publicIp" -Severity 'INFO'
                } else {
                    Write-Log "Warning: This stack doesn't appear to be created for the infrastructure (missing instance details)" -Severity 'WARN'
                }
            } catch {
                Write-Log "Warning: Unable to get instance details from existing stack" -Severity 'WARN'
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
            
            # Process events in reverse order
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
            
            # Get and display stack outputs
            $outputs = (Get-CFNStack -StackName $StackName).Outputs
            if ($outputs) {
                Write-Log "===================" -Severity 'INFO'
                $instanceId = ($outputs | Where-Object { $_.OutputKey -eq "InstanceId" }).OutputValue
                $publicIp = ($outputs | Where-Object { $_.OutputKey -eq "PublicIp" }).OutputValue
                Write-Log "Instance ID: $instanceId" -Severity 'INFO'
                Write-Log "Public IP: $publicIp" -Severity 'INFO'
                Write-Log "===================" -Severity 'INFO'
                
                # Write instance ID to file if found in outputs
                if ($instanceId) {
                    @{
                        InstanceId = $instanceId
                    } | ConvertTo-Json | Out-File $InstanceIdFile
                    Write-Log "Instance ID written to $InstanceIdFile" -Severity 'INFO'
                    Add-FileToGitignore
                }
                Write-Log "Please refer to README.md and deploy.ps1 in order to deploy the application to this instance." -Severity 'INFO'
            }
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
        }
    }
    catch {
        Write-Log "An error occurred: $_" -Severity 'ERROR'
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Severity 'ERROR'
    }
}

Main
    
   

