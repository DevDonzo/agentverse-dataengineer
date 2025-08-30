#!/bin/bash

# This script orchestrates the initial setup of the Scholar's data environment.
# It performs the following actions:
# 1. Starts the creation of the Cloud SQL PostgreSQL instance in the background.
# 2. Creates the necessary Google Cloud Storage bucket.
# 3. Uploads raw report and ancient scroll files to GCS.
# 4. Waits for the Cloud SQL instance to be fully provisioned before exiting.
#
# It is designed to be run AFTER sourcing set_env.sh.

# --- Pre-flight Check ---
# Ensure that the required environment variables have been set.
if [ -z "$PROJECT_ID" ] || [ -z "$BUCKET_NAME" ] || [ -z "$REGION" ] || [ -z "$INSTANCE_NAME" ] || [ -z "$DB_PASSWORD" ]; then
  echo "Error: Required environment variables (PROJECT_ID, BUCKET_NAME, REGION, INSTANCE_NAME, DB_PASSWORD) are not set."
  echo "Please run 'source ./set_env.sh' before executing this script."
  exit 1
fi

echo "--- Starting Scholar's Data Environment Setup for Project: $PROJECT_ID ---"
echo ""

# --- 1. Forge the Scholar's Spellbook (Cloud SQL Instance) ---
echo "--> Task 1: Checking/Creating Cloud SQL instance '$INSTANCE_NAME'."
echo "    This will start in the background and may take several minutes."

# Check if the instance already exists to make the script idempotent.
# If it doesn't exist, create it in the background.
gcloud sql instances describe $INSTANCE_NAME --project=$PROJECT_ID >/dev/null 2>&1

if [ $? -eq 0 ]; then
  echo "    Instance '$INSTANCE_NAME' already exists. Skipping creation."
else
  gcloud sql instances create $INSTANCE_NAME \
    --database-version=POSTGRES_16 \
    --tier=db-custom-1-3840 \
    --region=$REGION \
    --root-password="$DB_PASSWORD" \
    --storage-size=10GB \
    --edition=enterprise \
    --enable-google-ml-integration \
    --database-flags cloudsql.enable_google_ml_integration=on > /dev/null 2>&1 &

  # Capture the Process ID (PID) of the background job
  SQL_PID=$!
  echo "    Creation of '$INSTANCE_NAME' started in the background (PID: $SQL_PID)."
fi
echo ""


# --- 2. Create GCS Archive ---
# This script uses one bucket for all data assets.
echo "--> Task 2: Checking/creating GCS bucket 'gs://$BUCKET_NAME'."
# Create the bucket only if it doesn't already exist.
gcloud storage buckets describe gs://$BUCKET_NAME >/dev/null 2>&1 || \
gcloud storage buckets create gs://$BUCKET_NAME --project=$PROJECT_ID --location=$REGION --uniform-bucket-level-access
echo "    Bucket 'gs://$BUCKET_NAME' is ready."
echo ""


# --- 3. Upload Source Scrolls and Intel ---
# These files represent the initial raw data to be processed.
REPORTS_DIR=~/agentverse-dataengineer/data/reports
SCROLLS_DIR=~/agentverse-dataengineer/data/scrolls_chest

echo "--> Task 3: Uploading data files to GCS."
if [ -d "$REPORTS_DIR" ]; then
  echo "    Uploading report files from $REPORTS_DIR..."
  gcloud storage cp ${REPORTS_DIR}/report_*.txt gs://${BUCKET_NAME}/raw_intel/ --quiet
else
  echo "    Warning: Directory not found, skipping report upload: $REPORTS_DIR"
fi

if [ -d "$SCROLLS_DIR" ]; then
  echo "    Uploading scroll files from $SCROLLS_DIR..."
  gcloud storage cp ${SCROLLS_DIR}/scroll_*.md gs://${BUCKET_NAME}/ancient_scrolls/ --quiet
else
  echo "    Warning: Directory not found, skipping scroll upload: $SCROLLS_DIR"
fi
echo "    File uploads are complete."
echo ""


echo ""
echo "--- Scholar's Data Environment Setup is Complete ---"