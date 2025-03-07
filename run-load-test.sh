#!/bin/bash

# Default values
TEST_NAME="load-test-$(date +%s)"
TARGET_SERVICES="http://http-server"
LOW_VUS="10"
MEDIUM_VUS="50"
HIGH_VUS="100"
PEAK_VUS="200"
DURATION_MINUTES="5"
NAMESPACE="default"
DEPLOYMENT_NAME="edgedelta"
DEPLOYMENT_NAMESPACE="edgedelta"

function usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -n, --name NAME            Name for the test job (default: auto-generated)"
  echo "  -t, --targets URLS         Comma-separated target service URLs"
  echo "  --low-vus NUM              Number of VUs for low traffic tier"
  echo "  --medium-vus NUM           Number of VUs for medium traffic tier"
  echo "  --high-vus NUM             Number of VUs for high traffic tier"
  echo "  --peak-vus NUM             Number of VUs for peak traffic tier"
  echo "  -d, --duration MINUTES     Duration for each traffic tier in minutes, should be at least 2 minutes"
  echo "  --namespace NAMESPACE      Kubernetes namespace to create the job in"
  echo "  --watch                    Watch the job progress after creation"
  echo "  --deployment-name NAME     Name of the deployment to monitor"
  echo "  --deployment-ns NAMESPACE  Namespace of the deployment to monitor"
  echo "  -h, --help                 Show this help message"
  echo ""
  echo "Notes:"
  echo "  - This script uses a Kubernetes secret named 'load-test-credentials' which contains:"
  echo "      - access-key: AWS access key for S3 uploads (Not needed if running in AWS environment and has IAM role with S3 permissions)"
  echo "      - secret-key: AWS secret key for S3 uploads (Not needed if running in AWS environment and has IAM role with S3 permissions)"
  echo "      - region: AWS region (e.g., us-west-2) (Not needed if running in AWS environment and has IAM role with S3 permissions)"
  echo "      - bucket: S3 bucket name for reports (If S3 upload enabled, report will be uploaded to this bucket under prefix 'load-tests')"
  echo "      - slack-url: Slack webhook URL for notifications (Posts S3 url of the report)"
  echo "  - All credential fields are optional. If AWS credentials are present, reports will be"
  echo "    uploaded to S3. If Slack URL is present, notifications will be sent."
  echo "  - If no credentials are provided, the report will still be generated and available"
  echo "    in the pod, which you can access with kubectl commands."
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--name)
      TEST_NAME="$2"
      shift 2
      ;;
    -t|--targets)
      TARGET_SERVICES="$2"
      shift 2
      ;;
    --low-vus)
      LOW_VUS="$2"
      shift 2
      ;;
    --medium-vus)
      MEDIUM_VUS="$2"
      shift 2
      ;;
    --high-vus)
      HIGH_VUS="$2"
      shift 2
      ;;
    --peak-vus)
      PEAK_VUS="$2"
      shift 2
      ;;
    -d|--duration)
      DURATION_MINUTES="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --deployment-name)
      DEPLOYMENT_NAME="$2"
      shift 2
      ;;
    --deployment-ns)
      DEPLOYMENT_NAMESPACE="$2"
      shift 2
      ;;
    --watch)
      WATCH=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Check for prerequisites in the specified namespace
if ! kubectl -n $NAMESPACE get serviceaccount load-test-sa &>/dev/null; then
  echo "Error: Required service account 'load-test-sa' not found in namespace '$NAMESPACE'."
  echo "Run the setup script first: ./setup-load-test-prereqs.sh $NAMESPACE"
  exit 1
fi

SECRET_EXISTS=$(kubectl -n $NAMESPACE get secret load-test-credentials 2>/dev/null)
if [ -z "$SECRET_EXISTS" ]; then
  echo "Warning: Secret 'load-test-credentials' not found in namespace '$NAMESPACE'."
  echo "Reports will be generated but won't be uploaded to S3 or sent to Slack."
  echo "To enable these features, run: ./setup-load-test-prereqs.sh $NAMESPACE"
  echo "Then update the secret with your credentials."
  echo ""
fi

if [ $DURATION_MINUTES -lt 2 ]; then
  echo "Error: Duration must be at least 2 minutes."
  echo "You specified: $DURATION_MINUTES minutes"
  echo ""
  usage
fi

TMP_YAML=$(mktemp)
cat bench.yaml | \
  sed "s/{{TEST_NAME}}/$TEST_NAME/g" | \
  sed "s/{{DEPLOYMENT_NAME}}/$DEPLOYMENT_NAME/g" | \
  sed "s/{{DEPLOYMENT_NAMESPACE}}/$DEPLOYMENT_NAMESPACE/g" | \
  sed "s/{{DURATION_MINUTES}}/$DURATION_MINUTES/g" | \
  sed "s/{{LOW_VUS}}/$LOW_VUS/g" | \
  sed "s/{{MEDIUM_VUS}}/$MEDIUM_VUS/g" | \
  sed "s/{{HIGH_VUS}}/$HIGH_VUS/g" | \
  sed "s/{{PEAK_VUS}}/$PEAK_VUS/g" | \
  sed "s|{{TARGET_SERVICES}}|$TARGET_SERVICES|g" > $TMP_YAML

kubectl apply -n $NAMESPACE -f $TMP_YAML

rm $TMP_YAML

echo "Created load test job: $TEST_NAME in namespace $NAMESPACE"
echo ""
echo "To access the report once the job is complete:"
echo "1. Check job status:"
echo "   kubectl -n $NAMESPACE get job $TEST_NAME"
echo ""
echo "2. Find the pod name:"
echo "   kubectl -n $NAMESPACE get pods --selector=job-name=$TEST_NAME"
echo ""
echo "3. Copy the report to your local machine:"
echo "   kubectl -n $NAMESPACE cp POD_NAME:results/test-TIMESTAMP/report.html ./report.html -c report-generator"
echo "   (Replace POD_NAME and TIMESTAMP with actual values)"
echo ""

if [ "$WATCH" = true ]; then
  echo "Waiting for pod to be created..."
  POD_NAME=""
  while [ -z "$POD_NAME" ]; do
    POD_NAME=$(kubectl -n $NAMESPACE get pods --selector=job-name=$TEST_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$POD_NAME" ]; then
      echo -n "."
      sleep 2
    fi
  done
  
  echo "Pod created: $POD_NAME"
  # Wait for the pod to be ready
  echo "Waiting for pod to be ready..."
  READY=false
  while [ "$READY" = false ]; do
    POD_STATUS=$(kubectl -n $NAMESPACE get pod $POD_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$POD_STATUS" = "Running" ]; then
      READY=true
      echo "Pod is now running."
    else
      echo -n "."
      sleep 3
    fi
  done
  
  echo "Starting log stream..."
  kubectl -n $NAMESPACE logs -f $POD_NAME -c resource-monitor
fi