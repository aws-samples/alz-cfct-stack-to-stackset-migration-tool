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
# This script provides a means of migrating multiple stacksets in parallel by using nohup to call the migrate.sh script.
# This file can be edited to migrate stack instances from one stackset to another for the purpose of migrating customizations
# from ALZ to CfCT pipeline.  Replace the example calls in this script with the source and target stackset names accordingly.
# Lastly, modify the output file name to write the log output from the nohup execution. 

# Define required arguments for execution control.
if [ -z "$1" ]
    then
        echo "Please provide the mgmt account id: ./migrate_all_stacksets.sh <mgmt account id> <comma separated list of ids for accounts to be migrated>"
        exit 1
fi

if [ -z "$2" ]
    then 
        echo "Please provide at least one account to be migrated in a comma separated list of ids: ./migrate_all_stacksets.sh <mgmt account id> <comma separated list of ids for accounts to be migrated>"
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

PRIMARY_REGION=us-east-1
SECONDARY_REGION=us-west-2
STACKSET_ROLE=arn:aws:iam::$1:role/service-role/AWSControlTowerStackSetRole
# Create a top level directory for script artifacts.
# Prepare the artifact folder.
echo "Creating the folder structure for the script execution."
mkdir -p artifacts

# Edit the below nohup calls to include the correct source and target stackset names.  Edit the log names accordingly.
nohup ./migrate.sh AWS-Landing-Zone-Baseline-1stSourceStackset CustomControlTower-1stTargetStackset "$STACKSET_ROLE" AWSControlTowerExecution "$PRIMARY_REGION $SECONDARY_REGION" "$2" >>& artifacts/1stLogName.log &
nohup ./migrate.sh AWS-Landing-Zone-Baseline-2ndSourceStackset CustomControlTower-2ndTargetStackset "$STACKSET_ROLE" AWSControlTowerExecution "$PRIMARY_REGION" "$2" >>& artifacts/2ndLogName.log &
nohup ./migrate.sh AWS-Landing-Zone-Baseline-3rdSourceStackset CustomControlTower-3rdTargetStackset "$STACKSET_ROLE" AWSControlTowerExecution "$PRIMARY_REGION $SECONDARY_REGION" "$2" >>& artifacts/3rdLogName.log & # Remove the trailing ampersand at the last nohup call.

