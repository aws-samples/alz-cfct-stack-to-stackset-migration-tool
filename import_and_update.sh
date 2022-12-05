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

## Overview
# This script provides functionality for just importing stack instances and updating the target stackset.
# In situations where stack instances may have been deleted and retained manually, this script provides a means
# of importing those stack instances to the target stackset.

# Set arguments.
TARGET_STACK_SET_NAME=$1 # The name of the target CloudFormation StackSet.
CLOUDFORMATION_ADMIN_ROLE_ARN=$2 # The ARN of the CloudFormation admin role ARN.  
CLOUDFORMATION_EXECUTION_ROLE_NAME=$3 # The name of the CloudFormation execution role.
PRIMARY_REGION=$4 # The name of the primary region for the script execution.
SOURCE_STACK_SET_STACK_INSTANCE_ARNS=$5 # A list of instance arns to pass in.  Pass in space delimited list as follows: "arn1" "arn2" "arn3"

# Argument evaluators
# Define required arguments for execution control.
if [ -z "$1" ]
    then 
        echo "No target stack set name was provided."
        echo "In order to migrate stacks, please provide a target stack set name."
        exit 1
fi

if [ -z "$2" ]
    then
        echo "No CloudFormation admin role ARN was provided."
        echo "In order to update the target stack set, specify the CloudFormation administration role ARN."
        exit 1
fi

if [ -z "$3" ]
    then
        echo "No CloudFormation execution role name was provided."
        echo "In order to update the target stack set, specify the CloudFormation execution role name."
        exit 1
fi

if [ -z "$4" ]
    then
        echo "No primary region was specified."
        echo "Please specify the name of the primary region."
        exit 1
fi

if [ -z "$5" ]
    then
        echo "No list of source instance ARNs was provided."
        echo "Please specify space separated and double quote enclosed list of ARNs from the source stack set."
        exit 1
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

# Import all stack instances from the source stack set to the target stack set.
# Checks for the source instance ARNs and performs an import operation if provided.
if [[ -n "$SOURCE_STACK_SET_STACK_INSTANCE_ARNS" ]]
    then
        printf 'Importing stack instances to %s stack set.\n' "$TARGET_STACK_SET_NAME"
        IMPORT_OPERATION=$(aws cloudformation import-stacks-to-stack-set --stack-set-name "$TARGET_STACK_SET_NAME" --stack-ids "$SOURCE_STACK_SET_STACK_INSTANCE_ARNS" --region "$PRIMARY_REGION")
        IMPORT_OPERATION_ID=$(echo "$IMPORT_OPERATION" | jq -r '.OperationId')
        printf 'Operation ID: %s  \n' "$IMPORT_OPERATION_ID"   
        # Nested loop to check for FAILED status of the import stack to stack set operation.
        # We expect a FAILED condition due to tag mismatches between LZ pipeline and CfCT pipeline.
        STATUS_OP=""
        while [[ "$(aws cloudformation describe-stack-set-operation --stack-set-name "$TARGET_STACK_SET_NAME" --operation-id "$IMPORT_OPERATION_ID" --region "$PRIMARY_REGION" | jq -r '.StackSetOperation | .Status')" != "FAILED" &&
                 "$(aws cloudformation describe-stack-set-operation --stack-set-name "$TARGET_STACK_SET_NAME" --operation-id "$IMPORT_OPERATION_ID" --region "$PRIMARY_REGION" | jq -r '.StackSetOperation | .Status')" != "SUCCEEDED" ]]; do
            printf "Waiting for import operation to complete.\\n" 
            sleep 20
        done
        printf 'Operation ID: %s may have failed to import due to the following reason, which is ok if the following update command succeeds:\n' "$IMPORT_OPERATION_ID"
        aws cloudformation describe-stack-set-operation --stack-set-name "$TARGET_STACK_SET_NAME" --operation-id "$IMPORT_OPERATION_ID" --region "$PRIMARY_REGION" | jq -r '.StackSetOperation | .StatusReason'
        printf 'Completed importing stacks to the %s stack set.\n' "$TARGET_STACK_SET_NAME"
    else
        printf "Only the specified stack instance(s) will be migrated.\\n"
    fi

# Perform an update of the target stack set and wait for confirmation.
# Checks for the input ARNs and performs an update of the target stack if present.  We do not want to update the target stack if there is no reason to perform the operation.
if [[ -n "$SOURCE_STACK_SET_STACK_INSTANCE_ARNS" ]]
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
        printf "Failed to update the target stack set.\\n"
        printf "Check the target stack set for imported stack instances and validate manually.\\n"
    fi