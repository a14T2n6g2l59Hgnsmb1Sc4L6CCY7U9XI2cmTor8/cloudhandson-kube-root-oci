#!/bin/bash

# usage:
# bash ./bin/cicd.sh [push]

action="$3"
set -feu

export CLUSTER_ENV=$1
export CLUSTER_NAME=$2
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
export AWS_REGION="ap-south-1"

export SPLUNK_EFS_ID=$(aws efs describe-file-systems \
  --query "FileSystems[?Name == 'eks-${CLUSTER_NAME}-${CLUSTER_ENV}-splunk-efs'].[FileSystemId]" \
  --output text)

export SPLUNK_EFS_ACCESS_POINT_ID=$(aws efs describe-access-points \
  --query "AccessPoints[?Name == 'splunk-global-access-point' && FileSystemId == '${SPLUNK_EFS_ID}'].[AccessPointId]" \
  --output text)

AWS_ECR_REPOSITORY="eks/config/${CLUSTER_ENV}/${CLUSTER_NAME}/tooling/root-oci"

# step 0: Clean local repo
rm -rf generated deployed
mkdir -p generated deployed

bash ./bin/generate/generate.sh

# step 1: Generate configuration
kustomize build --enable-helm . | \
  envsubst '${AWS_ACCOUNT_ID},${AWS_REGION},${CLUSTER_ENV},${CLUSTER_NAME},${SPLUNK_EFS_ID},${SPLUNK_EFS_ACCESS_POINT_ID}' \
  > generated/manifests.yaml

# step 2: Validate yaml
kubeconform --summary \
  --schema-location default \
  --schema-location https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json \
  --skip CustomResourceDefinition,Kustomization,OCIRepository,Gateway,SecretStore \
  generated/

aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com

# step 3: Push Artifact => remetre les refs vers git
if [ "${action}" = "push" ]; then
  flux push artifact oci://${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${AWS_ECR_REPOSITORY}:latest \
    --path="./generated/" \
    --source="$(git config --get remote.origin.url)" \
    --revision="$(git tag --points-at HEAD)@sha1:$(git rev-parse HEAD)" \
    --provider aws
else
  # step 3: Get Diff
  flux pull artifact oci://${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${AWS_ECR_REPOSITORY}:latest \
    --output deployed \
    --provider aws

  diff -u deployed/manifests.yaml generated/manifests.yaml | colordiff
fi
