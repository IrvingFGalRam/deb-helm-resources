#!/bin/bash

# Save current worrking directory
CALL_DIR=$(pwd)

# Use absolute paths here
TERRAFORM_DIR= # Path to terraform apply
CREDENTIALS_FILE= # Path to credentials file

cd $TERRAFORM_DIR


# Get GCP EKS cluster context
echo "...Getting EKS cluster context"
gcloud container clusters get-credentials $(terraform output -raw kubernetes_cluster_name) --region $(terraform output -raw location)

# Creating Network File System server
echo "...Creating Network File System server"
kubectl create namespace nfs
kubectl -n nfs apply -f nfs/nfs-server.yaml
echo "...NFS SERVER"
export NFS_SERVER=$(kubectl -n nfs get service/nfs-server -o jsonpath="{.spec.clusterIP}")

# Secrets env vars (airflow vars and connections) to inject to pods
# using Terraform output data. This section will change if you are
# using a service provider different to AWS or if you need more or
# less variables for your implementation.

## Creating the cloud provider connection URI based on the content of
## the credentials path
#CREDENTIALS=$(head -2 $CREDENTIALS_FILE | tail -1)
#AWS_REGION=$(terraform output -raw region)
#AFCONN_GCP="aws://${CREDENTIALS/,/:}@?region_name=${AWS_REGION}"
echo "...GCP URI ${AFCONN_GCP}"
#google-cloud-platform://?extra__google_cloud_platform__key_path=%2Fkeys%2Fkey.json&extra__google_cloud_platform__scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcloud-platform&extra__google_cloud_platform__project=airflow&extra__google_cloud_platform__num_retries=5

## Creating the connection URI for the database you'll use in your project.
## You may not need to use this section if you work in GCP.
#DB_USER=$(terraform output -raw rds_username)
#DB_PASSWORD=$(terraform output -raw rds_password)
#DB_ENDPOINT=$(terraform output -raw rds_endpoint)
#DB_NAME=$(terraform output -raw rds_database)
AFCONN_POSTGRES="postgresql://"
echo "...POSTGRES URI ${AFCONN_POSTGRES}"

## Env vars for data related to the rest of the services
#AFVAR_BUCKET=$(terraform output -raw s3_bucket_name)
AFVAR_BUCKET="bucket"
echo "...Bucket URI ${AFVAR_BUCKET}"
#AFVAR_LOGREV_KEY=$(terraform output -raw s3_csv_log_reviews_key)
#AFVAR_MOVREV_KEY=$(terraform output -raw s3_csv_movie_review_key)
#AFVAR_USRPUR_KEY=$(terraform output -raw s3_csv_user_purchase_key)
#AFVAR_USRPUR_TABLE="user_purchase"
#AFVAR_USRPUR_SCHEMA="raw_data"
#AFVAR_USRPUR_QUERY="create_schema_and_table.sql"  # must match file name in Docker image.
#AFVAR_GLUEJOB=$(terraform output -raw gj_name)
#AFVAR_GLUE_SCRIPT=$(terraform output -raw gj_script_location)
#AFVAR_REGION=$(terraform output -raw region)
#AFVAR_ATHDB=$(terraform output -raw ath-db-name)
#AFVAR_ATHBUCKET=$(terraform output -raw ath-out-bucket)

cd $CALL_DIR

# Enable nfs server for cluster
echo "...kubectl create namespace storage..."
kubectl create namespace storage
echo "...helm repo add nfs-subdir-external-provisioner..."
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
echo "...helm install nfs-subdir-external-provisioner..."
# GitBash was prepending some path see https://stackoverflow.com/a/34386471
#MSYS_NO_PATHCONV=1 helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner --namespace storage --set nfs.server=10.136.12.165 --set nfs.path=/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --namespace storage \
    --set nfs.server=$NFS_SERVER \
    --set nfs.path=//
#helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner --namespace storage --set nfs.path="/" --set nfs.server=$NFS_SERVER
#echo "...Other helm install nfs-subdir-external-provisioner..."
#helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner --namespace storage --set nfs.server=$env:NFS_SERVER --set nfs.path=/


# Create airflow namespace
echo "...kubectl create namespace airflow..."
kubectl create namespace airflow
echo "..."
helm repo add apache-airflow https://airflow.apache.org

# Inject env vars calculated earlier as secrets
echo "...kubectl create secret generic af-connections"
kubectl create secret generic af-connections --from-literal=gcp=${AFCONN_GCP} --from-literal=postgres=${AFCONN_POSTGRES} --namespace airflow

echo "...kubectl create secret generic af-variables"
kubectl create secret generic af-variables --from-literal=bucket=${AFVAR_BUCKET} --namespace airflow
#    --from-literal=logrev_key=${AFVAR_LOGREV_KEY} \
#    --from-literal=movrev_key=${AFVAR_MOVREV_KEY} \
#    --from-literal=usrpur_key=${AFVAR_USRPUR_KEY} \
#    --from-literal=usrpur_table=${AFVAR_USRPUR_TABLE} \
#    --from-literal=usrpur_schema=${AFVAR_USRPUR_SCHEMA} \
#    --from-literal=usrpur_query=${AFVAR_USRPUR_QUERY} \
#    --from-literal=gluejob=${AFVAR_GLUEJOB} \
#    --from-literal=glue_script_location=${AFVAR_GLUE_SCRIPT} \
#    --from-literal=region=${AFVAR_REGION} \
#    --from-literal=athdb=${AFVAR_ATHDB} \
#    --from-literal=athbucket=${AFVAR_ATHBUCKET} \
#    --namespace airflow

# Install airflow after secrets set
echo "...Installing Airflow... please wait"
helm install airflow apache-airflow/airflow -n airflow -f values.yaml

echo "...Press any key to continue"
while [ true ] ; do
read -t 3 -n 1
if [ $? = 0 ] ; then
exit ;
else
echo "...waiting for the keypress"
fi
done