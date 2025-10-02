# Copyright 2025 Amazon.com, Inc. or its affiliates. All Rights Reserved.

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("ec2", "ecs")]
    [string]$DeploymentType,

    # Common parameters
    [string]$Region,
    [switch]$SkipAssumeRole,

    # EC2-specific parameters
    [Parameter(ParameterSetName="EC2")]
    [string]$publishDirectory,
    [Parameter(ParameterSetName="EC2")]
    [string]$EC2InstanceId,
    [Parameter(ParameterSetName="EC2")]
    [string]$S3Bucket,
    [Parameter(ParameterSetName="EC2")]
    [string]$S3Folder,
    [Parameter(ParameterSetName="EC2")]
    [string]$mainBinary,

    # ECS-specific parameters
    [Parameter(ParameterSetName="ECS")]
    [string]$ApplicationName,
    [Parameter(ParameterSetName="ECS")]
    [string]$ContainerImageUri,
    [Parameter(ParameterSetName="ECS")]
    [ValidateSet(256, 512, 1024, 2048, 4096)]
    [int]$Cpu = 256,
    [Parameter(ParameterSetName="ECS")]
    [ValidateSet(512, 1024, 2048, 4096, 8192, 16384)]
    [int]$Memory = 512,
    [Parameter(ParameterSetName="ECS")]
    [int]$ContainerPort = 80,
    [Parameter(ParameterSetName="ECS")]
    [string]$EnvironmentVariables = "{}",
    [Parameter(ParameterSetName="ECS")]
    [string]$HostHeader = "",
    [Parameter(ParameterSetName="ECS")]
    [string]$CwLogConfiguration = "",
    [Parameter(ParameterSetName="ECS")]
    [int]$TaskCount = 1,
    [Parameter(ParameterSetName="ECS")]
    [string]$HealthCheckPath = "/"
)

# Constants
$ssmS3BucketParam = "/transform/bucket-name"
$InstanceIdFile = "instance_id_from_infra_deployment.config"
$EcsTemplateFile = "application_deployment.yml"

# Defaults 
$defaults = @{
    # EC2 defaults
    MainBinary = "MvcMusicStore"
    # ECS defaults
    Region = "us-east-1"
    ApplicationName = ""
    ContainerImageUri = ""
    Cpu = "256"
    Memory = "512"
    ContainerPort = "5000"
    EnvironmentVariables = ""
    HostHeader = ""
    CwLogConfiguration = ""
    TaskCount = ""
    HealthCheckPath = ""
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

function Get-NextPriority {
    param($InfraConfig)
    
    $ListenerArn = $InfraConfig.AlbListenerArn

    $rulesJson = aws elbv2 describe-rules --listener-arn $ListenerArn | ConvertFrom-Json
    $priorities = $rulesJson.Rules | Where-Object { $_.Priority -ne 'default' } | ForEach-Object { [int]$_.Priority }
    
    if (-not $priorities) {
        return 1
    }
    
    $nextPriority = 1
    $sortedPriorities = $priorities | Sort-Object
    foreach ($p in $sortedPriorities) {
        if ($p -ne $nextPriority) {
            break
        }
        $nextPriority++
    }
    
    return $nextPriority
}


function Initialize-Parameters {
    param(
        [string]$DeploymentType,
        [string]$publishDirectory,
        [string]$EC2InstanceId,
        [string]$S3Bucket,
        [string]$S3Folder,
        [string]$mainBinary,
        [string]$ApplicationName,
        [string]$ContainerImageUri,
        [switch]$SkipAssumeRole
    )

    if ($DeploymentType -eq "ec2") {
        # EC2 Parameter Initialization (Keep existing logic)
        if (-not $mainBinary -and $defaults.MainBinary) {
            $mainBinary = $defaults.MainBinary
        }

        # Try to read EC2 instance ID from file if not provided
        if (-not $EC2InstanceId -and (Test-Path $InstanceIdFile)) {
            try {
                $instanceConfig = Get-Content $InstanceIdFile | ConvertFrom-Json
                $EC2InstanceId = $instanceConfig.InstanceId
                Write-Log "Found stored EC2 instance ID in $InstanceIdFile : $($EC2InstanceId)" -Severity 'INFO'
            }
            catch {
                Write-Log "Failed to read instance ID from file: $_" -Severity 'ERROR'
            }
        }

        # Collect missing required parameters for EC2
        $missingParams = @()
        foreach ($param in @{
            PublishDirectory = $publishDirectory
            EC2InstanceId = $EC2InstanceId
            MainBinary = $mainBinary
        }.GetEnumerator()) {
            if (-not $param.Value) {
                $missingParams += $param.Key
            }
        }

        # Validate publishDirectory for EC2
        if ($publishDirectory -and -not (Test-Path $publishDirectory -PathType Container)) {
            Write-Log "Publish Directory '$publishDirectory' does not exist" -Severity 'ERROR'
            exit 1
        }

        # Handle S3 bucket and folder for EC2
        try {
            if (-not $S3Bucket) {
                $S3Bucket = (Get-SSMParameter -Name $ssmS3BucketParam -WithDecryption $true).Value
            }

            if (-not $S3Bucket) {
                Write-Log "S3 bucket not provided and not found in SSM parameter" -Severity 'ERROR'
                exit 1
            }

            if (-not $S3Folder) {
                $currentDate = Get-Date -Format "yyyy-MM-dd"
                $S3Folder = "$mainBinary-$currentDate"
            }

            $s3 = @{
                Bucket = $S3Bucket
                Key = $S3Folder
            }
        }
        catch {
            Write-Log "Failed to get S3 bucket from SSM parameter: $_" -Severity 'ERROR'
            exit 1
        }
    }
    else {
        # ECS Parameter Initialization
        if (-not (Test-Path $InstanceIdFile)) {
            Write-Log "Infrastructure file not found: $InstanceIdFile" -Severity 'ERROR'
            Write-Log "Please run deploy_infra.ps1 first to setup ECS infrastructure" -Severity 'ERROR'
            exit 1
        }

        try {
            $bootstrapStack = Get-CFNStack -StackName "${ApplicationName}-bootstrap" -ErrorAction SilentlyContinue
            if (-not $bootstrapStack) {
                Write-Log "Bootstrap stack not found. Please deploy bootstrap template first." -Severity 'ERROR'
                exit 1
            }

            $infraConfig = Get-Content $InstanceIdFile | ConvertFrom-Json
            Write-Log "Infrastructure Config:" -Severity 'INFO'
            Write-Log ($infraConfig | ConvertTo-Json) -Severity 'INFO'
        
            # Add bootstrap outputs to infrastructure config
            $bootstrapOutputs = $bootstrapStack.Outputs
            $infraConfig | Add-Member -NotePropertyName "ExecutionRoleArn" -NotePropertyValue ($bootstrapOutputs | Where-Object { $_.OutputKey -eq "ExecutionRoleArn" }).OutputValue
            $infraConfig | Add-Member -NotePropertyName "TaskRoleArn" -NotePropertyValue ($bootstrapOutputs | Where-Object { $_.OutputKey -eq "TaskRoleArn" }).OutputValue

            # Validate required infrastructure values
            $requiredInfraFields = @(
                @{ Name = "VpcId"; Display = "VPC ID" },
                @{ Name = "PrivateSubnetIds"; Display = "Private Subnet IDs" },
                @{ Name = "AlbListenerArn"; Display = "ALB Listener ARN" },
                @{ Name = "EcsClusterName"; Display = "ECS Cluster Name" },
                @{ Name = "EcsSecurityGroupId"; Display = "ECS Security Group ID" }
            )

            $missingInfra = @()
            foreach ($field in $requiredInfraFields) {
                if (-not $infraConfig.($field.Name)) {
                    $missingInfra += $field.Display
                }
            }

            if ($missingInfra.Count -gt 0) {
                Write-Log "Missing required infrastructure values: $($missingInfra -join ', ')" -Severity 'ERROR'
                exit 1
            }
        }
        catch {
            Write-Log "Failed to read infrastructure configuration: $_" -Severity 'ERROR'
            exit 1
        }

        # Collect missing required parameters for ECS
        $missingParams = @()
        foreach ($param in @('ApplicationName', 'ContainerImageUri')) {
            if ([string]::IsNullOrEmpty((Get-Variable -Name $param).Value)) {
                $missingParams += $param
            }
        }
    }

    # Common parameter validation
    if ($missingParams.Count -gt 0) {
        Write-Log "Missing required parameters: $($missingParams -join ', ')" -Severity 'ERROR'
        Show-Usage
        exit 1
    }

    # Assume role if not skipped
    if (-not $SkipAssumeRole) {
        try {
            $config = Get-Content $InstanceIdFile | ConvertFrom-Json
            $clusterName = $config.EcsClusterName  # Changed this line to access property directly
            $ResourcePrefix = $clusterName -replace '-cluster$',''
            $roleArn = "arn:aws:iam::$((Get-STSCallerIdentity).Account):role/${ResourcePrefix}-Deployment-Role"

            Write-Log "Assuming role: $roleArn" -Severity 'INFO'
            $credentials = (Use-STSRole -RoleArn $roleArn -RoleSessionName "ApplicationDeploymentSession").Credentials
            Set-AWSCredential -AccessKey $credentials.AccessKeyId -SecretKey $credentials.SecretAccessKey -SessionToken $credentials.SessionToken -Scope Global
        }
        catch {
            Write-Log "Failed to assume role. Please verify that:" -Severity 'ERROR'
            Write-Log "1. The role '${ResourcePrefix}-Deployment-Role' exists in your account" -Severity 'ERROR'  # Updated error message
            Write-Log "2. Your IAM user/role has permission to assume this role" -Severity 'ERROR'
            Write-Log "3. The role trust policy allows your IAM user/role to assume it" -Severity 'ERROR'
            Write-Log "Error details: $_" -Severity 'ERROR'
            exit 1
        }
    }


    if ($DeploymentType -eq "ec2") {
        return @{
            PublishDirectory = $publishDirectory
            EC2InstanceId = $EC2InstanceId
            MainBinary = $mainBinary
            S3 = $s3
        }
    }
    else {
        return @{
            ApplicationName = $ApplicationName
            ContainerImageUri = $ContainerImageUri
            InfraConfig = $infraConfig
        }
    }
}

function Show-Usage {
    $defaultValues = ""
    foreach ($key in $defaults.Keys) {
        if ($defaults[$key]) {
            $defaultValues += "    -$key : $($defaults[$key])`n"
        }
    }

    Write-Log @"
Usage: 
    # For EC2 deployment:
    .\deploy.ps1 -DeploymentType ec2 `
                 -publishDirectory <publish-directory> `
                 -EC2InstanceId <instance-id> `
                 -S3Bucket <s3-bucket> `
                 -S3Folder <s3-folder> `
                 -mainBinary <main-binary> `
                 -SkipAssumeRole

    # For ECS deployment:
    .\deploy.ps1 -DeploymentType ecs `
                 -ApplicationName <app-name> `
                 -ContainerImageUri <image-uri> `
                 -Cpu <cpu-units> `
                 -Memory <memory-mb> `
                 -ContainerPort <port> `
                 -SkipAssumeRole

EC2 Parameters:
    -publishDirectory : Path to the directory containing the published application 
    -EC2InstanceId   : ID of the EC2 instance where the application will be deployed
    -S3Bucket        : S3 bucket for uploading the deployment package
    -S3Folder        : S3 folder/key prefix for the deployment package
    -mainBinary      : Name of the main executable binary

ECS Parameters:
    -ApplicationName     : Name of the application to deploy
    -ContainerImageUri   : URI of the container image to deploy
    -Cpu                : CPU units (256-4096)
    -Memory             : Memory in MB (512-16384)
    -ContainerPort      : Container port (default: 80)
    -EnvironmentVariables: Environment variables as JSON
    -HostHeader         : Host-based routing header
    -CwLogConfiguration : CloudWatch logging configuration
    -TaskCount          : Number of tasks to run
    -HealthCheckPath    : Health check path

Common Parameters:
    -DeploymentType     : Type of deployment (ec2 or ecs)
    -Region             : AWS region
    -SkipAssumeRole     : Skip assuming the deployment role

Default values:
$defaultValues

This script will:
    Assume the AWSTransformDotNET-Application-Deployment-Role for deployment permissions
    Read infrastructure details from $InstanceIdFile
    Deploy the application to either EC2 or ECS based on deployment type
    
Note: Run deploy_infra.ps1 first to create the infrastructure.
"@ -Severity 'INFO'
}

# Function to archive publish directory
function archive_publish_directory {
    param ($publishDir, $mainBinary)

    $parentDir = Split-Path -Parent $publishDir
    $archiveFile = Join-Path $parentDir "$mainBinary.zip"

    Write-Log "Starting to create archive from $publishDir" -Severity 'INFO'

    if (Test-Path $archiveFile) {
        Remove-Item -Path $archiveFile -Force -ErrorAction SilentlyContinue
    }

    try {
        Compress-Archive -Path "$publishDir\*" -DestinationPath $archiveFile -CompressionLevel Optimal -Force    }
    catch {
        Write-Log "Failed to create archive: $_" -Severity 'ERROR'
        exit 1
    }

    if (-not (Test-Path $archiveFile)) {
        Write-Log "Failed to create archive" -Severity 'ERROR'
        exit 1
    }

    # Get and display file size
    $fileSize = (Get-Item $archiveFile).Length
    $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
    Write-Log "Archive created successfully: $archiveFile ($fileSizeMB MB)" -Severity 'SUCCESS'

    return $archiveFile
}

# Function to upload to S3 with retries
function upload_to_s3 {
    param ($file, $bucket, $key, $zipFile)
    
    # Validate input parameters
    if (-not $file -or -not $bucket -or -not $key) {
        Write-Log "Missing required parameters for S3 upload" -Severity 'ERROR'
        Write-Log "File: $file" -Severity 'ERROR'
        Write-Log "Bucket: $bucket" -Severity 'ERROR'
        Write-Log "Key: $key" -Severity 'ERROR'
        exit 1
    }

    # Verify file exists
    if (-not (Test-Path $file)) {
        Write-Log "File does not exist: $file" -Severity 'ERROR'
        exit 1
    }

    $uploadKey =  "$key/$zipFile" 
    
    for ($i = 0; $i -lt 5; $i++) {
        try {
            Write-Log "Attempting S3 upload (attempt $($i+1)/5)" -Severity 'INFO'
            Write-S3Object -BucketName $bucket -Key $uploadKey -File $file -ErrorAction Stop
            Write-Log "Successfully uploaded to s3://$bucket/$uploadKey" -Severity 'SUCCESS'
            return
        } catch {
            $errorMessage = $_.Exception.Message
            Write-Log "Upload attempt $($i+1) failed: $errorMessage" -Severity 'ERROR'
            
            if ($_.Exception.Message -like "*The specified bucket does not exist*") {
                Write-Log "Bucket $bucket does not exist" -Severity 'ERROR'
                exit 1
            }
            
            if ($_.Exception.Message -like "*Access Denied*") {
                Write-Log "Access denied to bucket $bucket" -Severity 'ERROR'
                exit 1
            }

            $waitTime = [Math]::Pow(2, $i)
            Write-Log "Waiting $waitTime seconds before retry..." -Severity 'WARN'
            Start-Sleep -Seconds $waitTime
        }
    }
    Write-Log "Failed to upload to S3 after 5 attempts" -Severity 'ERROR'
    exit 1
}

# Function to check if EC2 instance exists
function Check-InstanceExists {
    param ($instanceId)
    try {
        $instance = Get-EC2Instance -InstanceId $instanceId -ErrorAction Stop
        $state = $instance.Instances[0].State.Name
        Write-Log "Instance $instanceId exists with state: $state" -Severity 'INFO'
        
        if ($state -eq 'terminated') {
            Write-Log "Instance $instanceId is terminated" -Severity 'ERROR'
            return $false
        }
        return $true
    }
    catch {
        Write-Log "Instance $instanceId does not exist or is not accessible: $_" -Severity 'ERROR'
        return $false
    }
}

# Function to check SSM agent status
function check_ssm_status {
    param ($instanceId)
    for ($i = 0; $i -lt 60; $i++) {
        $status = (Get-SSMInstanceInformation -Filter @{Key="InstanceIds";Values=$instanceId}).PingStatus
        Write-Log "Checking SSM agent status (attempt $($i+1)/60): $status" -Severity 'INFO'
        if ($status -eq 'Online') {
            return $true
        }
        Start-Sleep -Seconds 5
    }
    return $false
}

# Function to create systemd service file
function create_systemd {
    param($mainBinary, $publishDir, $dbConnectionStringLocation)

    $mainBinaryPath = ""
    $binaryFiles = Get-ChildItem -Path $publishDir -Name "$mainBinary*" -Recurse -File

    foreach ($binaryFile in $binaryFiles) {
        $filename = Split-Path $binaryFile -Leaf
        if ($filename -eq $mainBinary) {
            $mainBinaryPath = $binaryFile -replace "^$([regex]::Escape($publishDir))[\\/]", "" -replace "\\", "/"
            break
        }
    }

    if (!$mainBinaryPath) {
        $mainBinaryPath = $mainBinary
    }

    # Check for aws-transform-deploy.env file
    $environment = Test-Path (Join-Path $publishDir "aws-transform-deploy.env")

    $deployDir = "/var/www/$mainBinary"
    $execStart = "$deployDir/$mainBinaryPath"

    $serviceContent = @"
[Unit]
Description=$mainBinary .NET App
After=network.target

[Service]
WorkingDirectory=$deployDir
ExecStart=$execStart
"@

    if ($environment) {
        $serviceContent += "`nEnvironmentFile=$deployDir/aws-transform-deploy.env"
    }

    $serviceContent += @"

StandardOutput=append:/var/log/$mainBinary/system.out.log
StandardError=append:/var/log/$mainBinary/system.err.log
Restart=always
User=root
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true

[Install]
WantedBy=multi-user.target
"@

    $serviceContent | Out-File -FilePath "$publishDir\$mainBinary.service" -Encoding UTF8
}

# Function to trigger SSM command
function trigger_ssm_command {
    param ($instanceId, $bucket, $key, $mainBinary)
    $downloadPath =  "$key/$mainBinary.zip" 

    $commands = @"
MAIN_BINARY_NAME='$mainBinary'
DEPLOY_ROOT='/var/www'
DEPLOY_DIR=`$DEPLOY_ROOT/`$MAIN_BINARY_NAME
ZIP_FILE=/tmp/`$MAIN_BINARY_NAME.zip
LOG_DIR=/var/log/`$MAIN_BINARY_NAME

# Verify the archive is on the EC2 instance
if [ -f `$ZIP_FILE ]; then
  echo 'Zip file found at '`$ZIP_FILE
else
  echo 'Zip file not found at '`$ZIP_FILE
  exit 1
fi

# Install .NET 8 runtime and ASP.NET Core 8 runtime
sudo dnf install -y dotnet-runtime-8.0 --refresh --best --allowerasing
echo === dotnet 8.0 runtime is installed ===
sudo dnf install -y aspnetcore-runtime-8.0 --refresh --best --allowerasing
echo === aspnetcore 8.0 runtime is installed ===

# Stop and remove previous deployment service
sudo systemctl stop `$MAIN_BINARY_NAME.service || true
sudo systemctl disable `$MAIN_BINARY_NAME.service || true
sudo rm -f /etc/systemd/system/`$MAIN_BINARY_NAME.service

# Remove the previous deployment directory and create new ones
sudo rm -rf `$DEPLOY_DIR
sudo rm -rf `$LOG_DIR
mkdir -p `$DEPLOY_DIR
mkdir -p `$LOG_DIR

# Unzip the archive
unzip -q `$ZIP_FILE -d `$DEPLOY_DIR
rm `$ZIP_FILE

# Check if a environment file exists for logging
if [ -f `${DEPLOY_DIR}/aws-transform-deploy.env ]; then
    echo 'env file found'
else
    echo 'env file not found'
fi

# Check if a .service file exists and move to correct location
if [ -f `${DEPLOY_DIR}/`$MAIN_BINARY_NAME.service ]; then
    echo '.service file found'
    sudo mv `${DEPLOY_DIR}/`$MAIN_BINARY_NAME.service '/etc/systemd/system/'
else
    echo '.service file NOT found'
    exit 1
fi

MAIN_BINARY_FILE_PATH=`$(sudo systemctl show -p ExecStart `${MAIN_BINARY_NAME}.service | cut -d= -f4 | cut -d';' -f1)
echo 'Main binary path: '`$MAIN_BINARY_FILE_PATH
sudo chmod +x `$MAIN_BINARY_FILE_PATH


sudo systemctl daemon-reload
sudo systemctl enable `$MAIN_BINARY_NAME.service
sudo systemctl start `$MAIN_BINARY_NAME.service
echo "=== Printing systemctl status  ==="
sudo systemctl status `$MAIN_BINARY_NAME.service

echo "=== Printing system events by journalctl ==="
journalctl -u `$MAIN_BINARY_NAME.service -n 30

echo "=== system.out.log ==="
cat `$LOG_DIR/system.out.log

echo "=== system.err.log ==="
cat `$LOG_DIR/system.err.log
"@

    try {
        $json = @{
            sourceType = @("S3")
            sourceInfo = @("{`"path`":`"https://$bucket.s3.amazonaws.com/$downloadPath`"}")
            workingDirectory = @("/tmp")
            commandLine = @($commands)
        }

        $cmd = $null
        $maxRetries = 5
        $success = $false

        for ($i = 0; $i -lt $maxRetries; $i++) {
            try {
                $cmd = Send-SSMCommand -InstanceId $instanceId `
                    -DocumentName "AWS-RunRemoteScript" `
                    -Parameter $json `
                    -TimeoutSeconds 600
                $success = $true
                break
            } catch {
                $errorMessage = $_.Exception.Message
                Write-Log "Failed to send SSM command (attempt $($i+1)/$maxRetries): $errorMessage" -Severity 'ERROR'
                
                if ($errorMessage -like "*InvalidInstanceId*") {
                    Write-Log "Instance ID $instanceId is invalid" -Severity 'ERROR'
                    throw
                }
                
                if ($errorMessage -like "*AccessDenied*") {
                    Write-Log "Access denied when sending SSM command" -Severity 'ERROR'
                    throw
                }

                if ($i -eq ($maxRetries - 1)) {
                    Write-Log "Failed to send SSM command after $maxRetries attempts" -Severity 'ERROR'
                    throw
                }

                $waitTime = [Math]::Pow(2, $i)
                Write-Log "Waiting $waitTime seconds before retry..." -Severity 'WARN'
                Start-Sleep -Seconds $waitTime
            }
        }

        if (-not $success -or -not $cmd) {
            Write-Log "Failed to initiate SSM command" -Severity 'ERROR'
            throw "SSM command initiation failed"
        }

        $commandId = $cmd.CommandId
        Write-Log "SSM Command is initiated on EC2 $instanceId with ID: $commandId" -Severity 'SUCCESS'

        # Wait for command completion
        do {
            Start-Sleep -Seconds 5
            $result = Get-SSMCommandInvocation -CommandId $commandId -InstanceId $instanceId 
            Write-Log "Command Status: $($result.Status)" -Severity 'INFO'
        } while ($result.Status -eq "InProgress" -or $result.Status -eq "Pending")

        # Get command output
        $output = Get-SSMCommandInvocationDetail -CommandId $commandId -InstanceId $instanceId -PluginName "runShellScript"
        Write-Log "Command Output:" -Severity 'INFO'
        Write-Log $output.StandardOutputContent -Severity 'INFO'
        
        if ($result.Status -ne "Success") {
            Write-Log "Error Output:" -Severity 'ERROR'
            Write-Log $output.StandardErrorContent -Severity 'ERROR'
            throw "SSM command failed with status: $($result.Status)"
        }
    }
    catch {
        Write-Log "Failed to send SSM command" -Severity 'ERROR'
        throw
    }
}

# Function to cleanup the archive folder
function cleanup {
    param ($file)
    Remove-Item -Path $file -Force
}

# Function to check AWS PowerShell modules
function Install-RequiredModules {
    $requiredModules = @(
        "AWS.Tools.Common",
        "AWS.Tools.S3",
        "AWS.Tools.SimpleSystemsManagement",
        "AWS.Tools.SecurityToken",
        "AWS.Tools.EC2",
        "AWS.Tools.CloudFormation"
        "AWS.Tools.ElasticLoadBalancingV2"
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

function Deploy-EcsApplication {
    param (
        [string]$ApplicationName,
        [string]$ContainerImageUri,
        [PSObject]$InfraConfig,
        [int]$Cpu,
        [int]$Memory,
        [int]$ContainerPort,
        [string]$EnvironmentVariables,
        [string]$HostHeader,
        [string]$CwLogConfiguration,
        [int]$TaskCount,
        [string]$HealthCheckPath
    )

    $stackName = "$ApplicationName-app"
    
    try {
        try {
            $existingStack = Get-CFNStack -StackName $stackName -ErrorAction Stop
            Write-Log "Found existing application stack: $stackName" -Severity 'WARN'
            
            $confirmation = Read-Host "Are you sure you want to delete and recreate the application stack? (y/n)"
            if ($confirmation -ne 'y') {
                Write-Log "Deployment cancelled by user" -Severity 'INFO'
                return $false
            }

            Write-Log "Deleting stack $stackName..." -Severity 'WARN'
            Remove-CFNStack -StackName $stackName -Force
            Write-Log "Waiting for stack deletion to complete..." -Severity 'WARN'
            Wait-CFNStack -StackName $stackName
            Write-Log "Stack deletion completed" -Severity 'SUCCESS'
        }
        catch {
            Write-Log "No existing application stack found. Creating new stack." -Severity 'INFO'
        }

        $nextPriority = Get-NextPriority -InfraConfig $InfraConfig

        $cfnParams = @(
            @{ ParameterKey="ApplicationName"; ParameterValue=$ApplicationName }
            @{ ParameterKey="VpcId"; ParameterValue=$InfraConfig.VpcId }
            @{ ParameterKey="PrivateSubnetIds"; ParameterValue=$InfraConfig.PrivateSubnetIds }
            @{ ParameterKey="AlbListenerArn"; ParameterValue=$InfraConfig.AlbListenerArn }
            @{ ParameterKey="EcsClusterName"; ParameterValue=$InfraConfig.EcsClusterName }
            @{ ParameterKey="EcsSecurityGroupId"; ParameterValue=$InfraConfig.EcsSecurityGroupId }
            @{ ParameterKey="ContainerImageUri"; ParameterValue=$ContainerImageUri }
            @{ ParameterKey="Cpu"; ParameterValue=$Cpu.ToString() }
            @{ ParameterKey="Memory"; ParameterValue=$Memory.ToString() }
            @{ ParameterKey="OperatingSystem"; ParameterValue="Linux" }
            @{ ParameterKey="ContainerPort"; ParameterValue=$ContainerPort.ToString() }
            @{ ParameterKey="EnvironmentVariables"; ParameterValue=$EnvironmentVariables }
            @{ ParameterKey="HostHeader"; ParameterValue=$HostHeader }
            @{ ParameterKey="CwLogConfiguration"; ParameterValue=$CwLogConfiguration }
            @{ ParameterKey="TaskCount"; ParameterValue=$TaskCount.ToString() }
            @{ ParameterKey="HealthCheckPath"; ParameterValue=$HealthCheckPath }
            @{ ParameterKey="ListenerRulePriority"; ParameterValue=$nextPriority.ToString() }
        )

        Write-Log "Creating new application stack..." -Severity 'INFO'

        New-CFNStack -StackName $stackName `
                     -TemplateBody (Get-Content $EcsTemplateFile -Raw) `
                     -Parameter $cfnParams `
                     -Capability CAPABILITY_IAM `
                     -Tag @{Key="CreatedFor"; Value="AWSTransformDotNET"}

        Write-Log "Waiting for application deployment to complete..." -Severity 'WARN'

        $lastEvent = $null
        $timeout = New-TimeSpan -Minutes 15
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        while ($true) {
            if ($stopwatch.Elapsed -gt $timeout) {
                Write-Log "Deployment timed out after 15 minutes" -Severity 'ERROR'
                return $false           
            }
            
            $status = (Get-CFNStack -StackName $stackName).StackStatus
            $events = Get-CFNStackEvent -StackName $stackName | Select-Object -First 10
            
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

        if ((Get-CFNStack -StackName $stackName).StackStatus -eq 'CREATE_COMPLETE') {
            Write-Log "Application stack created successfully" -Severity 'SUCCESS'
            return $true
        }
        else {
            Write-Log "Application stack creation failed" -Severity 'ERROR'
            return $false
        }
    }
    catch {
        Write-Log "Failed to deploy application: $_" -Severity 'ERROR'
        return $false
    }
}


function Main {
    Install-RequiredModules

    $params = Initialize-Parameters -DeploymentType $DeploymentType `
                                   -publishDirectory $publishDirectory `
                                   -EC2InstanceId $EC2InstanceId `
                                   -S3Bucket $S3Bucket `
                                   -S3Folder $S3Folder `
                                   -mainBinary $mainBinary `
                                   -ApplicationName $ApplicationName `
                                   -ContainerImageUri $ContainerImageUri `
                                   -SkipAssumeRole:$SkipAssumeRole

    try {
        if ($DeploymentType -eq "ec2") {
            $publishDirectory = $params.PublishDirectory
            $EC2InstanceId = $params.EC2InstanceId
            $mainBinary = $params.MainBinary
            $s3 = $params.S3

            # Check if instance exists
            if (-not (Check-InstanceExists $EC2InstanceId)) {
                Write-Log "Cannot proceed with deployment - instance validation failed" -Severity 'ERROR'
                exit 1
            }

            # Create systemd file
            create_systemd $mainBinary $publishDirectory 

            # Create the Zip File
            $zip = archive_publish_directory $publishDirectory $mainBinary

            # Upload to S3
            upload_to_s3 $zip $s3.Bucket $s3.Key "$mainBinary.zip"

            # Cleanup
            cleanup $zip

            # Check SSM status and trigger command
            if (-not (check_ssm_status $EC2InstanceId)) {
                Write-Log "SSM agent did not go online after 5 minutes" -Severity 'ERROR'
                exit 1
            }

            # Trigger the SSM Command
            trigger_ssm_command $EC2InstanceId $s3.Bucket $s3.Key $mainBinary

            # Get EC2 instance public IP
            $instanceInfo = Get-EC2Instance -InstanceId $EC2InstanceId
            $publicIp = $instanceInfo.Instances[0].PublicIpAddress
            
            Write-Log "====================================" -Severity 'SUCCESS'
            if ($publicIp) {
                Write-Log "Application deployed to EC2 instance with public IP $publicIp" -Severity 'SUCCESS'
            } else {
                Write-Log "Could not determine instance public IP" -Severity 'WARN'
                Write-Log "Please check EC2 console for instance IP address" -Severity 'WARN'
            }

            Write-Log "Application is placed in /var/www/$mainBinary/ and started as systemd service /etc/systemd/system/$mainBinary.service" -Severity 'SUCCESS'
            Write-Log "Please refer to README.md file on how to access logs and general troubleshooting tips" -Severity 'SUCCESS'
            Write-Log "====================================" -Severity 'SUCCESS'
        }
        else {
            # ECS deployment logic
            $success = Deploy-EcsApplication `
                -ApplicationName $params.ApplicationName `
                -ContainerImageUri $params.ContainerImageUri `
                -InfraConfig $params.InfraConfig `
                -Cpu $Cpu `
                -Memory $Memory `
                -ContainerPort $ContainerPort `
                -EnvironmentVariables $EnvironmentVariables `
                -HostHeader $HostHeader `
                -CwLogConfiguration $CwLogConfiguration `
                -TaskCount $TaskCount `
                -HealthCheckPath $HealthCheckPath

            if (-not $success) {
                exit 1
            }
        }
    }
    catch {
        Write-Log "An error occurred: $_" -Severity 'ERROR'
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Severity 'ERROR'
        exit 1
    }
    exit 0
}

# Start script execution
Main