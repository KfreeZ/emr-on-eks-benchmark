#!/bin/bash

# // Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# // SPDX-License-Identifier: MIT-0

# Define params
# export EKSCLUSTER_NAME=eks-nvme
# export AWS_REGION=us-east-1
export OSS_SPARK_SVCACCT_NAME=oss
export OSS_NAMESPACE=oss
export EMR_NAMESPACE=emr
export EKS_VERSION=1.26
export EMRCLUSTER_NAME=emr-on-$EKSCLUSTER_NAME
export ROLE_NAME=${EMRCLUSTER_NAME}-execution-role
export ACCOUNTID=$(aws sts get-caller-identity --query Account --output text)
export S3TEST_BUCKET=${EMRCLUSTER_NAME}-${ACCOUNTID}-${AWS_REGION}

echo "==============================================="
echo "  setup IAM roles ......"
echo "==============================================="

# create S3 bucket for application
if [ $AWS_REGION=="us-east-1" ]; then
  aws s3api create-bucket --bucket $S3TEST_BUCKET --region $AWS_REGION
else
  aws s3api create-bucket --bucket $S3TEST_BUCKET --region $AWS_REGION --create-bucket-configuration LocationConstraint=$AWS_REGION
fi
# Create a job execution role (https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/creating-job-execution-role.html)
cat >/tmp/job-execution-policy.json <<EOL
{
    "Version": "2012-10-17",
    "Statement": [ 
        {
            "Effect": "Allow",
            "Action": ["s3:PutObject","s3:DeleteObject","s3:GetObject","s3:ListBucket"],
            "Resource": [
              "arn:aws:s3:::${S3TEST_BUCKET}",
              "arn:aws:s3:::${S3TEST_BUCKET}/*",
              "arn:aws:s3:::kfz-blogpost-sparkoneks/blog/BLOG_TPCDS-TEST-1G-partitioned/*",
              "arn:aws:s3:::kfz-blogpost-sparkoneks/blog/BLOG_TPCDS-TEST-3T-partitioned/*",
              "arn:aws:s3:::kfz-blogpost-sparkoneks"
            ]
        }, 
        {
            "Effect": "Allow",
            "Action": [ "logs:PutLogEvents", "logs:CreateLogStream", "logs:DescribeLogGroups", "logs:DescribeLogStreams", "logs:CreateLogGroup" ],
            "Resource": [ "arn:aws:logs:*:*:*" ]
        }
    ]
}
EOL

cat >/tmp/trust-policy.json <<EOL
{
  "Version": "2012-10-17",
  "Statement": [ {
      "Effect": "Allow",
      "Principal": { "Service": "eks.amazonaws.com" },
      "Action": "sts:AssumeRole"
    } ]
}
EOL

aws iam create-policy --policy-name $ROLE_NAME-policy --policy-document file:///tmp/job-execution-policy.json
aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file:///tmp/trust-policy.json
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::$ACCOUNTID:policy/$ROLE_NAME-policy




echo "============================================================================="
echo "  Upload project examples to S3 ......"
echo "============================================================================="
aws s3 sync examples/ s3://$S3TEST_BUCKET/app_code/

#echo "============================================================================="
#echo "  Create ECR for eks-spark-benchmark utility docker image ......"
#echo "============================================================================="
#export ECR_URL="$ACCOUNTID.dkr.ecr.$AWS_REGION.amazonaws.com"
#aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
#aws ecr create-repository --repository-name eks-spark-benchmark --image-scanning-configuration scanOnPush=true
## get EMR on EKS base image
#export SRC_ECR_URL=755674844232.dkr.ecr.us-east-1.amazonaws.com
#aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $SRC_ECR_URL
#docker pull $SRC_ECR_URL/spark/emr-6.5.0:latest
## Custom image on top of the EMR Spark runtime
#docker build -t $ECR_URL/eks-spark-benchmark:emr6.5 -f docker/benchmark-util/Dockerfile --build-arg SPARK_BASE_IMAGE=$SRC_ECR_URL/spark/emr-6.5.0:latest .
## push
#aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL
#docker push $ECR_URL/eks-spark-benchmark:emr6.5

echo "Finished, proceed to submitting a job"
