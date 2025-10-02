#!/bin/bash

# Copyright 2025 Amazon.com, Inc. or its affiliates. All Rights Reserved.

set -e

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTANCE_ID_FILE="instance_id_from_infra_deployment.config"
readonly ECS_TEMPLATE_FILE="application_deployment.yml"
readonly GITIGNORE_PATH=".gitignore"

# Default values (to be saturated by ATX agent)
DEFAULTS_region="us-east-1"
DEFAULTS_application_name=""
DEFAULTS_container_image_uri=""
DEFAULTS_cpu="256"
DEFAULTS_memory="512"
DEFAULTS_container_port="80"
DEFAULTS_environment_variables="{}"
DEFAULTS_host_header=""
DEFAULTS_path_pattern="/*"
DEFAULTS_cw_log_configuration=""
DEFAULTS_task_count="1"
DEFAULTS_health_check_path="/"

# Logging function
write_log() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local severity="$1"
    local message="$2"
    echo "[$timestamp] [$severity] $message"
}

# Show usage information
show_usage() {
    cat << EOF
Usage: 
    ./deploy.sh --deployment-type <type> [options]

Required Parameters:
    --deployment-type       : Deployment type (ecs)
    --application-name      : Name of the application
    --image-uri             : Container image URI

Optional Parameters:
    --region                : AWS region
    --skip-assume-role      : Skip assuming deployment role
    --cpu                   : CPU units (256, 512, 1024, 2048, 4096)
    --memory                : Memory in MB (512, 1024, 2048, 4096, 8192, 16384)
    --container-port        : Container port (default: 80)
    --environment-variables : Environment variables as JSON
    --host-header           : Host-based routing header
    --path-pattern          : Path-based routing pattern
    --cw-log-configuration  : CloudWatch logging configuration
    --task-count            : Number of tasks to run (default: 1)
    --health-check-path     : Health check path (default: /)

Example:
    ./deploy.sh \\
      --deployment-type ecs \\
      --application-name "myapp" \\
      --image-uri "public.ecr.aws/nginx/nginx:latest" \\
      --cpu 256 \\
      --memory 512
EOF
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in aws jq; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        write_log "ERROR" "Missing required dependencies: ${missing_deps[*]}"
        write_log "ERROR" "Please install: ${missing_deps[*]}"
        exit 1
    fi
    
}

# Get next available priority for ALB listener rule
get_next_priority() {
    # Get ALB ARN from the infrastructure file
    ALB_ARN=$(cat "$INSTANCE_ID_FILE" | jq -r '.[] | select(.OutputKey=="AlbArn") | .OutputValue')
    
    LISTENER_ARN=$(aws elbv2 describe-listeners \
      --load-balancer-arn $ALB_ARN \
      --query 'Listeners[0].ListenerArn' \
      --output text)
    
    # Get all existing priorities except 'default'
    PRIORITIES=$(aws elbv2 describe-rules \
      --listener-arn $LISTENER_ARN \
      --query 'Rules[?Priority!=`default`].Priority' \
      --output text)
    
    if [ -z "$PRIORITIES" ]; then
        echo "1"
        return
    fi

    # Convert priorities to array and sort numerically
    PRIORITY_ARRAY=($(echo $PRIORITIES | tr ' ' '\n' | sort -n))
    
    # Find first available number
    NEXT_PRIORITY=1
    for p in "${PRIORITY_ARRAY[@]}"; do
        if [ "$p" -ne "$NEXT_PRIORITY" ]; then
            break
        fi
        NEXT_PRIORITY=$((NEXT_PRIORITY + 1))
    done
    
    echo "$NEXT_PRIORITY"
}



# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --deployment-type)
                DEPLOYMENT_TYPE="$2"
                shift 2
                ;;
            --application-name)
                APPLICATION_NAME="$2"
                shift 2
                ;;
            --image-uri)
                CONTAINER_IMAGE_URI="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --skip-assume-role)
                SKIP_ASSUME_ROLE=true
                shift
                ;;
            --cpu)
                CPU="$2"
                shift 2
                ;;
            --memory)
                MEMORY="$2"
                shift 2
                ;;
            --container-port)
                CONTAINER_PORT="$2"
                shift 2
                ;;
            --environment-variables)
                ENVIRONMENT_VARIABLES="$2"
                shift 2
                ;;
            --host-header)
                HOST_HEADER="$2"
                shift 2
                ;;
            --path-pattern)
                PATH_PATTERN="$2"
                shift 2
                ;;
            --cw-log-configuration)
                CW_LOG_CONFIGURATION="$2"
                shift 2
                ;;
            --task-count)
                TASK_COUNT="$2"
                shift 2
                ;;
            --health-check-path)
                HEALTH_CHECK_PATH="$2"
                shift 2
                ;;
            *)
                write_log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Validate input parameters
validate_parameters() {
    local missing_params=()

    # Required parameters
    [[ -z "$DEPLOYMENT_TYPE" ]] && missing_params+=("--deployment-type")
    [[ -z "$APPLICATION_NAME" ]] && missing_params+=("--application-name")
    [[ -z "$CONTAINER_IMAGE_URI" ]] && missing_params+=("--image-uri")

    
    if [[ ${#missing_params[@]} -gt 0 ]]; then
        write_log "ERROR" "Missing required parameters: ${missing_params[*]}"
        show_usage
        exit 1
    fi
    

    # Validate deployment type
    if [[ "$DEPLOYMENT_TYPE" != "ecs" ]]; then
        write_log "ERROR" "Invalid deployment type. Only 'ecs' is currently supported"
        exit 1
    fi

    # Validate CPU values
    if [[ -n "$CPU" && ! "$CPU" =~ ^(256|512|1024|2048|4096)$ ]]; then
        write_log "ERROR" "Invalid CPU value. Must be one of: 256, 512, 1024, 2048, 4096"
        exit 1
    fi

    # Validate Memory values
    if [[ -n "$MEMORY" && ! "$MEMORY" =~ ^(512|1024|2048|4096|8192|16384)$ ]]; then
        write_log "ERROR" "Invalid Memory value. Must be one of: 512, 1024, 2048, 4096, 8192, 16384"
        exit 1
    fi

    # Set defaults if not provided
    CPU=${CPU:-$DEFAULTS_cpu}
    MEMORY=${MEMORY:-$DEFAULTS_memory}
    CONTAINER_PORT=${CONTAINER_PORT:-$DEFAULTS_container_port}
    TASK_COUNT=${TASK_COUNT:-$DEFAULTS_task_count}
    HEALTH_CHECK_PATH=${HEALTH_CHECK_PATH:-$DEFAULTS_health_check_path}
    ENVIRONMENT_VARIABLES=${ENVIRONMENT_VARIABLES:-$DEFAULTS_environment_variables}
    HOST_HEADER=${HOST_HEADER:-$DEFAULTS_host_header}
    PATH_PATTERN=${PATH_PATTERN:-$DEFAULTS_path_pattern}
    CW_LOG_CONFIGURATION=${CW_LOG_CONFIGURATION:-$DEFAULTS_cw_log_configuration}
}

# Add file to .gitignore
add_to_gitignore() {
    local file_to_ignore="$1"
    
    if [ -f "$GITIGNORE_PATH" ]; then
        if ! grep -q "^$file_to_ignore$" "$GITIGNORE_PATH"; then
            echo "$file_to_ignore" >> "$GITIGNORE_PATH"
        fi
    else
        echo "$file_to_ignore" > "$GITIGNORE_PATH"
    fi
}

# Get common error solution
get_common_error_solution() {
    local error_message="$1"
    
    case "$error_message" in
        *"role cannot be assumed"*)
            echo "Check IAM role permissions and trust relationships"
            ;;
        *"VPC"*)
            echo "Verify VPC ID exists and is in the correct region"
            ;;
        *"ECS cluster"*)
            echo "Verify ECS cluster name is correct and the cluster exists"
            ;;
        *"certificate"*)
            echo "Ensure the ACM certificate ARN is valid and in the correct region"
            ;;
        *)
            echo "Review CloudFormation documentation and check AWS Console for more details"
            ;;
    esac
}

# Assume deployment role
assume_deployment_role() {
    [[ "$SKIP_ASSUME_ROLE" == "true" ]] && return

    write_log "INFO" "Assuming deployment role..."
    
    local account_id role_arn credentials
    account_id=$(aws sts get-caller-identity --query Account --output text)
    local resource_prefix=$(jq -r '.[] | select(.OutputKey=="EcsClusterName") | .OutputValue' "$INSTANCE_ID_FILE" | sed 's/-cluster$//')
    local role_arn="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/${resource_prefix}-Deployment-Role"
    
    if ! credentials=$(aws sts assume-role \
        --role-arn "$role_arn" \
        --role-session-name "ApplicationDeploymentSession" \
        --output json 2>/dev/null); then
        write_log "ERROR" "Failed to assume role. Please verify that:"
        write_log "ERROR" "1. The role exists in your account"
        write_log "ERROR" "2. Your IAM user/role has permission to assume this role"
        write_log "ERROR" "3. The role trust policy allows your IAM user/role to assume it"
        exit 1
    fi

    export AWS_ACCESS_KEY_ID=$(echo "$credentials" | jq -r .Credentials.AccessKeyId)
    export AWS_SECRET_ACCESS_KEY=$(echo "$credentials" | jq -r .Credentials.SecretAccessKey)
    export AWS_SESSION_TOKEN=$(echo "$credentials" | jq -r .Credentials.SessionToken)
    write_log "INFO" "Successfully assumed deployment role"
}

# Validate infrastructure configuration
validate_infrastructure() {
    if [[ ! -f "$INSTANCE_ID_FILE" ]]; then
        write_log "ERROR" "Infrastructure file not found: $INSTANCE_ID_FILE"
        write_log "ERROR" "Please run deploy_infra.sh first to setup ECS infrastructure"
        exit 1
    fi

    local infra_config
    infra_config=$(cat "$INSTANCE_ID_FILE")
    
    write_log "DEBUG" "Infrastructure file contents:"
    echo "$infra_config"
    
    # Extract values from infrastructure config
    VPC_ID=$(echo "$infra_config" | jq -r '.[] | select(.OutputKey=="VpcId") | .OutputValue')
    PRIVATE_SUBNETS=$(echo "$infra_config" | jq -r '.[] | select(.OutputKey=="PrivateSubnetIds") | .OutputValue')
    ALB_LISTENER_ARN=$(echo "$infra_config" | jq -r '.[] | select(.OutputKey=="AlbListenerArn") | .OutputValue')
    ECS_CLUSTER_NAME=$(echo "$infra_config" | jq -r '.[] | select(.OutputKey=="EcsClusterName") | .OutputValue')
    ECS_SECURITY_GROUP_ID=$(echo "$infra_config" | jq -r '.[] | select(.OutputKey=="EcsSecurityGroupId") | .OutputValue')

    # Validate that all required values are present
    local missing_values=()
    [[ -z "$VPC_ID" ]] && missing_values+=("VpcId")
    [[ -z "$PRIVATE_SUBNETS" ]] && missing_values+=("PrivateSubnetIds")
    [[ -z "$ALB_LISTENER_ARN" ]] && missing_values+=("AlbListenerArn")
    [[ -z "$ECS_CLUSTER_NAME" ]] && missing_values+=("EcsClusterName")
    [[ -z "$ECS_SECURITY_GROUP_ID" ]] && missing_values+=("EcsSecurityGroupId")

    
    if [[ ${#missing_values[@]} -gt 0 ]]; then
        write_log "ERROR" "Missing required infrastructure values: ${missing_values[*]}"
        exit 1
    fi
    

    write_log "INFO" "Infrastructure validation successful"
}

# Create CloudFormation stack parameters
create_stack_parameters() {
    # Get next available priority
    local next_priority=$(get_next_priority)

    local parameters="[
        {
            \"ParameterKey\": \"ApplicationName\",
            \"ParameterValue\": \"$APPLICATION_NAME\"
        },
        {
            \"ParameterKey\": \"VpcId\",
            \"ParameterValue\": \"$VPC_ID\"
        },
        {
            \"ParameterKey\": \"PrivateSubnetIds\",
            \"ParameterValue\": \"$PRIVATE_SUBNETS\"
        },
        {
            \"ParameterKey\": \"AlbListenerArn\",
            \"ParameterValue\": \"$ALB_LISTENER_ARN\"
        },
        {
            \"ParameterKey\": \"EcsClusterName\",
            \"ParameterValue\": \"$ECS_CLUSTER_NAME\"
        },
        {
            \"ParameterKey\": \"EcsSecurityGroupId\",
            \"ParameterValue\": \"$ECS_SECURITY_GROUP_ID\"
        },
        {
            \"ParameterKey\": \"ContainerImageUri\",
            \"ParameterValue\": \"$CONTAINER_IMAGE_URI\"
        },
        {
            \"ParameterKey\": \"Cpu\",
            \"ParameterValue\": \"$CPU\"
        },
        {
            \"ParameterKey\": \"Memory\",
            \"ParameterValue\": \"$MEMORY\"
        },
        {
            \"ParameterKey\": \"ContainerPort\",
            \"ParameterValue\": \"$CONTAINER_PORT\"
        },
        {
            \"ParameterKey\": \"EnvironmentVariables\",
            \"ParameterValue\": \"$ENVIRONMENT_VARIABLES\"
        },
        {
            \"ParameterKey\": \"HostHeader\",
            \"ParameterValue\": \"$HOST_HEADER\"
        },

        {
            \"ParameterKey\": \"CwLogConfiguration\",
            \"ParameterValue\": \"$CW_LOG_CONFIGURATION\"
        },
        {
            \"ParameterKey\": \"TaskCount\",
            \"ParameterValue\": \"$TASK_COUNT\"
        },
        {
            \"ParameterKey\": \"HealthCheckPath\",
            \"ParameterValue\": \"$HEALTH_CHECK_PATH\"
        },
        {
            \"ParameterKey\": \"ListenerRulePriority\",
            \"ParameterValue\": \"$next_priority\"
        }
    ]"

    echo "$parameters"
}

# Deploy CloudFormation stack
deploy_stack() {
    local stack_name="$APPLICATION_NAME-app"
    local parameters="$1"

    write_log "INFO" "Starting deployment of stack: $stack_name"
    write_log "DEBUG" "Parameters being sent to CloudFormation:"
    echo "$parameters" | jq '.'

    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "$stack_name" &>/dev/null; then
        write_log "INFO" "Updating existing stack..."
        if ! aws cloudformation update-stack \
            --stack-name "$stack_name" \
            --template-body "file://$ECS_TEMPLATE_FILE" \
            --parameters "$parameters" \
            --capabilities CAPABILITY_IAM \
            --tags Key=CreatedFor,Value=AWSTransformDotNET; then
            write_log "ERROR" "Failed to initiate stack update"
            return 1
        fi
    else
        write_log "INFO" "Creating new stack..."
        if ! aws cloudformation create-stack \
            --stack-name "$stack_name" \
            --template-body "file://$ECS_TEMPLATE_FILE" \
            --parameters "$parameters" \
            --capabilities CAPABILITY_IAM \
            --tags Key=CreatedFor,Value=AWSTransformDotNET; then
            write_log "ERROR" "Failed to initiate stack creation"
            return 1
        fi
    fi

    # Monitor stack progress
    write_log "INFO" "Monitoring stack deployment progress..."
    while true; do
        local stack_status
        stack_status=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query 'Stacks[0].StackStatus' \
            --output text)
        
        case "$stack_status" in
            *COMPLETE)
                write_log "SUCCESS" "Stack deployment completed successfully"
                return 0
                ;;
            *FAILED|*ROLLBACK_*)
                write_log "ERROR" "Stack deployment failed"
                aws cloudformation describe-stack-events \
                    --stack-name "$stack_name" \
                    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED`]' \
                    --output json | jq -r '.[] | "Failed resource: \(.LogicalResourceId)\nReason: \(.ResourceStatusReason)"'
                return 1
                ;;
            *)
                write_log "INFO" "Current stack status: $stack_status"
                sleep 10
                ;;
        esac
    done
}

# Main execution
main() {
    check_dependencies
    parse_arguments "$@"
    validate_parameters

    # Set region if provided
    [[ -n "$REGION" ]] && export AWS_DEFAULT_REGION="$REGION"

    # Assume deployment role unless skipped
    assume_deployment_role

    # Validate infrastructure
    write_log "INFO" "Validating infrastructure configuration..."
    validate_infrastructure
    write_log "INFO" "Infrastructure validation complete"

    # Create stack parameters
    write_log "INFO" "Creating stack parameters..."
    local stack_parameters
    stack_parameters=$(create_stack_parameters)
    write_log "INFO" "Stack parameters created successfully"
    write_log "DEBUG" "Stack parameters:"
    echo "$stack_parameters" | jq '.'

    # Deploy stack
    write_log "INFO" "Initiating stack deployment..."
    if deploy_stack "$stack_parameters"; then
        write_log "SUCCESS" "Application deployed successfully"
        add_to_gitignore "$INSTANCE_ID_FILE"
        exit 0
    else
        write_log "ERROR" "Application deployment failed"
        local error_solution=$(get_common_error_solution "$(aws cloudformation describe-stack-events \
            --stack-name "$APPLICATION_NAME-app" \
            --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].ResourceStatusReason' \
            --output text)")
        write_log "INFO" "Possible solution: $error_solution"
        exit 1
    fi
}

# Start script execution
main "$@"