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

# This file provides a wrapper to execute multiple calls of the status_report.sh script for checking the results of an ALZ to CfCT pipeline
# stackset migration activity.  Refer to the example below and customize this file accordingly to check multiple stacks.
# Provide the names of the source stackset and the target stackset as depicted below.

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

# Primary region
PRIMARY_REGION=us-east-1

# Define required arguments for execution control.
./status_report.sh AWS-Landing-Zone-Baseline-1stSourceStackset CustomControlTower-1stTargetStackset $PRIMARY_REGION
./status_report.sh AWS-Landing-Zone-Baseline-2ndSourceStackset CustomControlTower-2ndTargetStackset $PRIMARY_REGION
./status_report.sh AWS-Landing-Zone-Baseline-3rdSourceStackset CustomControlTower-3rdTargetStackset $PRIMARY_REGION
