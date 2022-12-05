#!/usr/bin/env bash
set -e
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
PRIMARY_REGION=$3 # The primary region for command execution.  Can be passed as a variable, but is otherwise determined from the 

# Define required arguments for execution control.
if [ -z "$1" ]
    then
        echo "No source stack set name was provided."
        exit 1
fi

if [ -z "$2" ]
    then 
        echo "No target stack set name was provided."
        exit 1
fi

if [ -z "$3" ]
    then 
        echo "No primary region was provided."
fi

# Create input and output variables for file operations.
REGIONFILE=./artifacts/"$SOURCE_STACK_SET_NAME"/source_stack_region_list.txt
INPUTFILE=./artifacts/"$SOURCE_STACK_SET_NAME"/source_stack_account_list_arns.txt
OUTPUTFILE=./artifacts/"$SOURCE_STACK_SET_NAME"/"$SOURCE_STACK_SET_NAME"-to-"$TARGET_STACK_SET_NAME"-status-report.csv

# Create a CSV file structure for the report.
echo "Source StackSet, Target StackSet, Stack ID, Stack Region, Stack Status, Stack Status Reason" >> "$OUTPUTFILE"

# Set an array for the migrated region list from the migrate.sh script artifact file if a region is not specified.
# Fails if no region is found or specified.
if [ -z "$PRIMARY_REGION" ]
    then
        SOURCE_REGION_LIST=()
        while IFS=' ' read -r line || [[ "$line" ]]; do
            SOURCE_REGION_LIST+=("$line")
        done < "$REGIONFILE"
        # Determine the primary region from the region input file. 
        printf -v PRIMARY_REGION '%s' "${SOURCE_REGION_LIST%% *}"
        printf 'The primary region is: %s \n' "$PRIMARY_REGION"
fi

if [ -z "$PRIMARY_REGION" ]
    then
        printf "No primary region was provided as an input.\\n "
        printf "No primary region was identified from the migrate.sh artifact file.\\n"
        printf "Rerun the script and specify the primary region or check the artifact source for the region file.\\n"
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

# Set an array for the migrated ARN list from the migrate.sh script artifact file.
SOURCE_ARN_LIST=()
while IFS=' ' read -r line || [[ "$line" ]]; do
    SOURCE_ARN_LIST+=("$line")
done < "$INPUTFILE"
printf "The following ARNs will be checked for status:\\n"
echo "${SOURCE_ARN_LIST[@]}"

# Retrieve the status and set it to a variable for each ARN.
for i in "${SOURCE_ARN_LIST[@]}"; do
    # Set a variable equal to the ARN for the stack ID parameter.
    STACK_ID=$i
    printf 'The stack ID for this stack ARN is %s.\n' "$STACK_ID"
    # Get the region name from the ARN.
    STACK_REGION=$(cut -d ':' -f 4 <<< "$i")
    printf 'The AWS region for this stack ARN is %s.\n' "$STACK_REGION"
    # Get the account ID from the ARN.
    STACK_ACCOUNT_ID=$(cut -d ':' -f 5 <<< "$i")
    printf 'The AWS account ID for this stack ARN is %s.\n' "$STACK_ACCOUNT_ID"
    STACK_STATUS=$(aws cloudformation describe-stack-instance --stack-set-name "$TARGET_STACK_SET_NAME" --stack-instance-account "$STACK_ACCOUNT_ID" --stack-instance-region "$STACK_REGION" --region "$PRIMARY_REGION" | jq -r '.StackInstance | .Status')
    STACK_STATUS_REASON=$(aws cloudformation describe-stack-instance --stack-set-name "$TARGET_STACK_SET_NAME" --stack-instance-account "$STACK_ACCOUNT_ID" --stack-instance-region "$STACK_REGION" --region "$PRIMARY_REGION" | jq -r '.StackInstance | .StatusReason')
    echo "${SOURCE_STACK_SET_NAME}, ${TARGET_STACK_SET_NAME}, ${STACK_ID}, ${STACK_REGION}, ${STACK_STATUS}, ${STACK_STATUS_REASON}" >> "$OUTPUTFILE"
    printf 'Status retrieved for stack instance %s.\n' "$STACK_ID"
done
# Append the ARN status to the report file.
printf 'The CSV report file has been appended.  View the status report at %s.\n' "$OUTPUTFILE"