#!/usr/bin/env bash
set -xe
###############################################################################
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# This file is licensed under the Apache License, Version 2.0 (the "License").
#
# You may not use this file except in compliance with the License. A copy of
# the License is located at http://aws.amazon.com/apache2.0/.
#
# This file is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.
###############################################################################
#
# This script contains general-purpose functions that are used throughout
# the AWS Command Line Interface (AWS CLI) code examples that are maintained
# in the repo at https://github.com/awsdocs/aws-doc-sdk-examples.
#
# They are intended to abstract functionality that is required for the tests
# to work without cluttering up the code. The intent is to ensure that the
# purpose of the code is clear.

# Set arguments.
SOURCE_STACK_SET_NAME=$1 # The name of the source CloudFormation StackSet.
TARGET_STACK_SET_NAME=$2 # The name of the target CloudFormation StackSet.
CLOUDFORMATION_ADMIN_ROLE_ARN=$3 # The ARN of the CloudFormation admin role ARN.  
CLOUDFORMATION_EXECUTION_ROLE_NAME=$4 # The name of the CloudFormation execution role.
SOURCE_STACK_SET_REGIONS=$5 # A list of regions to delete the source stack instances from.  Required to delete stack instances from the source stack set.
SOURCE_STACK_ACCOUNT_LIST=$6 # A specific list of account IDs for the source StackSet.  Allows limiting the migration to a subset of specific stacks in the stackset.

# Usage and Overview
# This script is designed to perform stack instance migrations from a source stack set to a target stack set.
# As part of this process, you may specify a list of source stack account IDs for stack instances to move.
# If SOURCE_STACK_ACCOUNT_LIST is provided, only those stacks in the source stack set will be migrated.
# In order to update the target stack once stack instances are migrated, please provide the CLOUDFORMATION_ADMIN_ROLE_ARN and the CLOUDFORMATION_EXECUTION_ROLE.
#
#
# Run the command as seen below to execute the migrate script:
# ./migrate.sh [SOURCE_STACK_SET_NAME] [TARGET_STACK_SET_NAME] [CLOUDFORMATION_ADMIN_ROLE_ARN] [CLOUDFORMATION_EXECUTION_ROLE_NAME] [SOURCE_STACK_SET_REGIONS] [SOURCE_STACK_ACCOUNT_LIST]

# Define required arguments for execution control.
if [ -z "$1" ]
    then
        echo "No source stack set name was provided."
        exit 1
fi

if [ -z "$2" ]
    then 
        echo "No target stack set name was provided."
        echo "In order to migrate stacks, please provide a target stack set name."
        exit 1
fi

if [ -z "$3" ]
    then
        echo "No CloudFormation admin role ARN was provided."
        echo "In order to update the target stack set, specify the CloudFormation administration role ARN."
        exit 1
fi

if [ -z "$4" ]
    then
        echo "No CloudFormation execution role name was provided."
        echo "In order to update the target stack set, specify the CloudFormation execution role name."
        exit 1
fi

if [ -z "$5" ]
    then
        echo "No source stack set regions were specified."
        echo "Please specify the list of regions from the source stack set."
        exit 1
fi

if [ -z "$6" ]
    then
        echo "No source stack account list was provided."
        echo "In order to migrate specific stack instances, specify a list of AWS Account IDs for the stacks to be migrated."
fi

# Check for prereqs.
if ! command -v jq &> /dev/null
then
    echo "jq could not be found, please install jq."
    exit
fi

if ! command -v aws &> /dev/null
then
    echo "AWS CLI could not be found, please install AWS CLI version 2 or higher."
    exit
fi


AWS_CLI_MAJOR_VERSION=$(aws --version 2>&1 | cut -d " " -f1 | cut -d "/" -f2 | cut -d "." -f1)
if [ "$AWS_CLI_MAJOR_VERSION" -lt 2 ]
then 
    echo "Upgrade AWS CLI version to 2.x $(aws --version 2>&1)" 
    exit 
fi

# Return the primary region from the list.  All AWS CLI commands will execute against the primary region.
printf -v PRIMARY_REGION "%s" "${SOURCE_STACK_SET_REGIONS%% *}"
printf 'The primary region is: %s \n' "$PRIMARY_REGION"

# Prepare the artifact subfolders.
printf "Creating the folder structure for the script execution.\\n"
mkdir -p artifacts/"$SOURCE_STACK_SET_NAME"

# Evaluate the source stack set and retrieve a list of stack instances.
printf 'Retrieving a list of stack instances belonging to the %s stack set...\n' "$SOURCE_STACK_SET_NAME"
SOURCE_STACK_SET_INSTANCES=$( \
    aws cloudformation list-stack-instances --stack-set-name "$SOURCE_STACK_SET_NAME" --region "$PRIMARY_REGION"
)

# Retrieve the Account IDs from the stack instances to create an output list for other functions.
SOURCE_STACK_SET_ACCOUNT_IDS=$(echo "$SOURCE_STACK_SET_INSTANCES" | jq -r '.Summaries[] | .Account') 
if [[ -n "$SOURCE_STACK_SET_ACCOUNT_IDS" ]]
    then
        printf 'Creating a list of account IDs for the stack instances in the %s stack set.\n' "$SOURCE_STACK_SET_NAME"
        printf '%s' "$SOURCE_STACK_SET_ACCOUNT_IDS" | tee ./artifacts/"$SOURCE_STACK_SET_NAME"/source_stack_set_account_ids.txt
        printf "Stack instance account IDs list created successfully.\\n"
    else
        printf 'No stack instances were found belonging to the %s stack set.\n' "$SOURCE_STACK_SET_NAME"
        printf 'Verify that the %s stack set contains stack instances and try again.\n' "$SOURCE_STACK_SET_NAME"
        exit 1
    fi

# Retrieve the stack instance ARNs from the stack instances to create an output list for other functions.
SOURCE_STACK_SET_STACK_INSTANCE_ARNS=$(echo "$SOURCE_STACK_SET_INSTANCES" | jq -r '.Summaries[] | .StackId')
if [[ -n "$SOURCE_STACK_SET_STACK_INSTANCE_ARNS" ]]
    then
        printf '%s' "$SOURCE_STACK_SET_STACK_INSTANCE_ARNS" | tee ./artifacts/"$SOURCE_STACK_SET_NAME"/source_stack_set_instance_arns.txt
        printf "Stack instance ARNs list created successfully.\\n"
    else 
        printf 'No stack instances were found belonging to the %s stack set.\n' "$SOURCE_STACK_SET_NAME"
        printf 'Verify that the %s stack set contains stack instances and try again.\n' "$SOURCE_STACK_SET_NAME"
        exit 1
    fi

# Create an output artifacts containing the ARNs, regions, and account IDs for the stack instances being migrated.
if [[ -n "$SOURCE_STACK_ACCOUNT_LIST" ]]
    then
        # Create an array using the SOURCE_STACK_ACCOUNT_LIST.
        printf "Generating an array from the account list input.\\n"
        IFS=, read -a SOURCE_STACK_ACCOUNT_ARRAY <<<"${SOURCE_STACK_ACCOUNT_LIST}"
        # printf -v SOURCE_ACCOUNTS '%s ' "${SOURCE_STACK_ACCOUNT_ARRAY[@]}"
        printf '%s' "${SOURCE_STACK_ACCOUNT_ARRAY[@]}" | tee ./artifacts/"$SOURCE_STACK_SET_NAME"/source_stack_account_list.txt
        printf "Generating an array from the region list input.\\n"
        IFS=' ' read -a SOURCE_STACK_REGION_ARRAY <<<"${SOURCE_STACK_SET_REGIONS}"
        printf -v SOURCE_REGIONS '%s' "${SOURCE_STACK_REGION_ARRAY[@]}"
        printf '%s' "${SOURCE_STACK_REGION_ARRAY[@]}" | tee ./artifacts/"$SOURCE_STACK_SET_NAME"/source_stack_region_list.txt
        # Create artifacts for script execution.
        SOURCE_STACKSET_ARNS=./artifacts/"$SOURCE_STACK_SET_NAME"/source_stack_set_instance_arns.txt
        SOURCE_ACCOUNT_LIST=./artifacts/"$SOURCE_STACK_SET_NAME"/source_stack_account_list.txt
        SOURCE_ACCOUNT_LIST_ARNS=./artifacts/"$SOURCE_STACK_SET_NAME"/source_stack_account_list_arns.txt
        SOURCE_REGION_LIST=./artifacts/"$SOURCE_STACK_SET_NAME"/source_stack_region_list.txt
        #SOURCE_MIGRATION_LIST=./artifacts/"$SOURCE_STACK_SET_NAME"/source_migration_list.txt
        # Run grep to filter on the account list for ARN IDs and output to file.
        printf "Creating an output file containing the source stack account list ARNs.\\n"
        SOURCE_LIST=$(grep -f "${SOURCE_ACCOUNT_LIST}" "${SOURCE_STACKSET_ARNS}" > "${SOURCE_ACCOUNT_LIST_ARNS}")
        # Run grep to filter the ARNs based on the specified region list.
        printf "Filtering the source stack account list ARNs by the region list.\\n"
        printf '%s\n' "${SOURCE_LIST[@]}"
        SOURCE_ARNS=$(grep -f "${SOURCE_REGION_LIST}" "${SOURCE_ACCOUNT_LIST_ARNS}")
        printf "The following ARN IDs are matched by account ID and region for migration:\\n"
        printf '%s\n' "${SOURCE_ARNS[@]}"
    else
        printf "A source stack instance list was provided.\\n"
    fi

# If the SOURCE_STACK_INSTANCE_LIST is not provided, use the SOURCE_STACK_SET_INSTANCE_IDS.
if [[ -n "$SOURCE_STACK_ACCOUNT_LIST" ]]
    then
        printf 'The source stack instance list will be used rather than the list of stack IDs from the %s stack set.\n' "$SOURCE_STACK_SET_NAME"
        printf "Generating an array of stacks to migrate.\\n"
        IFS=, read -a STACKS_TO_MIGRATE <<<"${SOURCE_STACK_ACCOUNT_ARRAY[@]}"
    else
        printf "A source stack account list was not provided.\\n"
        printf "Continuing...\\n"
        printf 'The script will migrate all stack instances in the %s stack set.\n' "$SOURCE_STACK_SET_NAME"
        IFS=, read -a STACKS_TO_MIGRATE <<<"${SOURCE_STACK_SET_ACCOUNT_IDS[@]}"
    fi
echo $STACKS_TO_MIGRATE

# Print out the list of stack instances to be migrated.
printf "The following account IDs will have stacks migrated:\\n"
printf '%s\n' "${STACKS_TO_MIGRATE[@]}"
printf "Stack instances will now be migrated.\\n"
printf "Source instances will be deleted and retained.\\n"

# Delete and retain specified stacks from the source stack set.
# Will NOT perform destructive actions.  RETAINS the stack instance in the account.
if [[ -n "$SOURCE_STACK_ACCOUNT_LIST" ]]
    then
        printf 'Deleting the specified stack instances from the %s stack set.\n' "$SOURCE_STACK_SET_NAME"
        printf 'Deleting stack instance(s) for accounts %s in the %s stackset.\n' "$SOURCE_STACK_ACCOUNT_LIST" "$SOURCE_STACK_SET_NAME"
        DELETE_OPERATION=$(aws cloudformation delete-stack-instances --stack-set-name "$SOURCE_STACK_SET_NAME" --deployment-targets Accounts="${SOURCE_STACK_ACCOUNT_LIST}" --regions "$SOURCE_STACK_SET_REGIONS" --retain-stacks --region "$PRIMARY_REGION" --operation-preferences RegionConcurrencyType=PARALLEL,FailureToleranceCount=9,MaxConcurrentCount=10)
        DELETE_OPERATION_ID=$(echo "$DELETE_OPERATION" | jq -r '.OperationId')
        printf 'Operation ID: %s \n' "$DELETE_OPERATION_ID"
        # Nested loop to check for SUCCEEDED status of the delete stack instance operation.
        while [ "$(aws cloudformation describe-stack-set-operation --stack-set-name "$SOURCE_STACK_SET_NAME" --operation-id "$DELETE_OPERATION_ID" --region "$PRIMARY_REGION" | jq -r '.StackSetOperation | .Status')" != "SUCCEEDED" ]; do
            printf "Waiting for delete operation to complete.\\n" 
            sleep 10
        done 

        printf 'Completed deleting stacks from the %s stack set.\n' "$SOURCE_STACK_SET_NAME"
    else
        printf "Continuing...\\n"
    fi

# Delete and retain all stack instances for the source stack set if evaluated TRUE.
# Will NOT perform destructive actions.  RETAINS the stack instance in the account.
if [[ -z "$SOURCE_STACK_ACCOUNT_LIST" ]]
    then
        printf 'Deleting all stack instances from the %s stack set.\n' "$SOURCE_STACK_SET_NAME"

        printf 'Deleting stack instance(s) in the %s stackset.\n' "$SOURCE_STACK_SET_NAME"
        ALL_DELETE_OPERATION=$(aws cloudformation delete-stack-instances --stack-set-name "$SOURCE_STACK_SET_NAME" --deployment-targets Accounts="${SOURCE_STACK_SET_ACCOUNT_IDS}" --regions "$SOURCE_STACK_SET_REGIONS" --retain-stacks --region "$PRIMARY_REGION" --operation-preferences RegionConcurrencyType=PARALLEL,FailureToleranceCount=9,MaxConcurrentCount=10)
        ALL_DELETE_OPERATION_ID=$(echo "$ALL_DELETE_OPERATION" | jq -r '.OperationId')
        printf 'Operation ID: %s \n' "$ALL_DELETE_OPERATION_ID"
        # Nested loop to check for SUCCEEDED status of the delete stack instance operation.
        while [ "$(aws cloudformation describe-stack-set-operation --stack-set-name "$SOURCE_STACK_SET_NAME" --operation-id "$ALL_DELETE_OPERATION_ID" --region "$PRIMARY_REGION" | jq -r '.StackSetOperation | .Status')" != "SUCCEEDED" ]; do
            printf "Waiting for delete operation to complete.\\n" 
            sleep 10
        done 
        printf 'Successfully deleted and retained stack instance(s) for accounts %s in the %s stackset.\n' "${SOURCE_STACK_ACCOUNT_LIST}" "$SOURCE_STACK_SET_NAME"   

        printf 'Completed deleting stacks from the %s stack set.\n' "$SOURCE_STACK_SET_NAME"
    else
        printf "Continuing...\\n"
    fi

# Import specified stack instances from the source stack set to the target stack set.
if [[ -n "$SOURCE_STACK_ACCOUNT_LIST" && -n "$SOURCE_ARNS" ]]
    then
        printf 'Importing the specified stack instances from the %s stack set.\n' "$SOURCE_STACK_SET_NAME"
        IMPORT_OPERATION=$(aws cloudformation import-stacks-to-stack-set --stack-set-name "$TARGET_STACK_SET_NAME" --stack-ids "$SOURCE_ARNS" --region "$PRIMARY_REGION")
        IMPORT_OPERATION_ID=$(echo "$IMPORT_OPERATION" | jq -r '.OperationId')
        printf 'Operation ID: %s \n' "$IMPORT_OPERATION_ID"    
        # Nested loop to check for FAILED status of the import stack to stack set operation.
        # We expect a FAILED condition due to tag mismatches between LZ pipeline and CfCT pipeline.
        while [[ "$(aws cloudformation describe-stack-set-operation --stack-set-name "$TARGET_STACK_SET_NAME" --operation-id "$IMPORT_OPERATION_ID" --region "$PRIMARY_REGION" | jq -r '.StackSetOperation | .Status')" != "FAILED" &&
                 "$(aws cloudformation describe-stack-set-operation --stack-set-name "$TARGET_STACK_SET_NAME" --operation-id "$IMPORT_OPERATION_ID" --region "$PRIMARY_REGION" | jq -r '.StackSetOperation | .Status')" != "SUCCEEDED" ]]; do
            printf "Waiting for import operation to complete.\\n" 
            sleep 20
        done
        printf 'Operation ID: %s may have failed to import due to the following reason, which is ok if the following update command succeeds:\n' "$IMPORT_OPERATION_ID" 
        aws cloudformation describe-stack-set-operation --stack-set-name "$TARGET_STACK_SET_NAME" --operation-id "$IMPORT_OPERATION_ID" --region "$PRIMARY_REGION" | jq -r '.StackSetOperation | .StatusReason'
        printf 'Completed importing stacks to the %s stack set.\n' "$TARGET_STACK_SET_NAME"
    else
        printf "Continuing...\\n"
    fi

# Import all stack instances from the source stack set to the target stack set.
if [[ -z "$SOURCE_STACK_ACCOUNT_LIST" && -n "$SOURCE_STACK_SET_STACK_INSTANCE_ARNS" ]]
    then
        printf 'Importing all stack instances from the %s stack set.\n' "$SOURCE_STACK_SET_NAME"
        ALL_IMPORT_OPERATION=$(aws cloudformation import-stacks-to-stack-set --stack-set-name "$TARGET_STACK_SET_NAME" --stack-ids "$SOURCE_STACK_SET_STACK_INSTANCE_ARNS" --region "$PRIMARY_REGION")
        ALL_IMPORT_OPERATION_ID=$(echo "$ALL_IMPORT_OPERATION" | jq -r '.OperationId')
        printf 'Operation ID: %s \n' "$ALL_IMPORT_OPERATION_ID"    
        # Nested loop to check for FAILED status of the import stack to stack set operation.
        # We expect a FAILED condition due to tag mismatches between LZ pipeline and CfCT pipeline.
        while [[ "$(aws cloudformation describe-stack-set-operation --stack-set-name "$TARGET_STACK_SET_NAME" --operation-id "$ALL_IMPORT_OPERATION_ID" --region "$PRIMARY_REGION" | jq -r '.StackSetOperation | .Status')" != "FAILED" &&
                 "$(aws cloudformation describe-stack-set-operation --stack-set-name "$TARGET_STACK_SET_NAME" --operation-id "$ALL_IMPORT_OPERATION_ID" --region "$PRIMARY_REGION" | jq -r '.StackSetOperation | .Status')" != "SUCCEEDED" ]]; do
            printf "Waiting for import operation to complete.\\n" 
            sleep 20
        done
        printf 'Operation ID: %s may have failed to import due to the following reason, which is ok if the following update command succeeds:\n' "$ALL_IMPORT_OPERATION_ID" 
        aws cloudformation describe-stack-set-operation --stack-set-name "$TARGET_STACK_SET_NAME" --operation-id "$ALL_IMPORT_OPERATION_ID" --region "$PRIMARY_REGION" | jq -r '.StackSetOperation | .StatusReason'
        printf 'Completed importing stacks to the %s stack set.\n' "$TARGET_STACK_SET_NAME"
    else
        printf "Only the specified stack instance(s) will be migrated.\\n"
    fi

# Perform an update of the target stack set and wait for confirmation.
if [[ -n "${STACKS_TO_MIGRATE[*]}" ]]
    then
        printf 'Triggering stack set update on the %s stack set.\n' "$TARGET_STACK_SET_NAME"
        UPDATE_OPERATION=$(aws cloudformation update-stack-set --stack-set-name "$TARGET_STACK_SET_NAME" --use-previous-template --administration-role-arn "$CLOUDFORMATION_ADMIN_ROLE_ARN" --execution-role-name "$CLOUDFORMATION_EXECUTION_ROLE_NAME" --capabilities CAPABILITY_NAMED_IAM --region "$PRIMARY_REGION")
        UPDATE_OPERATION_ID=$(echo "$UPDATE_OPERATION" | jq -r '.OperationId')
        printf 'Operation ID: %s \n' "$UPDATE_OPERATION_ID"
        while [ "$(aws cloudformation describe-stack-set-operation --stack-set-name "$TARGET_STACK_SET_NAME" --operation-id "$UPDATE_OPERATION_ID" --region "$PRIMARY_REGION" | jq -r '.StackSetOperation | .Status')" != "SUCCEEDED" ]; do
            printf "Waiting for update operation to complete.\\n"   
            sleep 20
        done
        printf 'Completed updating the %s stack set.\n' "$TARGET_STACK_SET_NAME"
    else
        printf 'Failed to update the %s stack set.\n' "$TARGET_STACK_SET_NAME"
        printf 'Check the %s stack set for imported stack instances and validate manually.\n' "$TARGET_STACK_SET_NAME"
    fi

./status_report.sh $SOURCE_STACK_SET_NAME $TARGET_STACK_SET_NAME $PRIMARY_REGION

# Print closing summary.
printf "Stack instance migration complete.\\n"

