# Kubernetes HTTP Traffic Load Testing And Resource Monitoring Tool

Utility for running controlled load tests against applications running in Kubernetes clusters. This utility provides a way to simulate traffic patterns with increasing load tiers and measure the impact on your application's resource usage.

## Overview

This load testing utility consists of:

1. A Kubernetes job template (`bench.yaml`) that defines the load test configuration
2. A shell script (`run-load-test.sh`) to easily configure and run load tests
3. A multi-container setup with:
   - Resource monitoring container
   - K6 load testing container
   - Report generation container

## Prerequisites

- Kubernetes cluster with access configured via `kubectl`
- Service account `load-test-sa` in the target namespace
- Optional: Secret `load-test-credentials` for S3 upload and Slack notifications

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/edgedelta/k8s-traffic-bench.git
   ```

2. Make the scripts executable:
   ```bash
   chmod +x setup-load-test-prereqs.sh
   chmod +x run-load-test.sh
   ```

3. Run the setup script to create required service accounts and permissions:
   ```bash
   ./setup-load-test-prereqs.sh default  # Replace 'default' with your namespace
   ```

4. (Optional) Deploy the included sample HTTP server:
   ```bash
   kubectl apply -f http-server.yaml
   ```
   
   This creates a simple Nginx-based HTTP server with 3 replicas that you can use for testing. This is provided only as a convenient target for tests, but you can test against any service in your cluster.

## Usage

Basic usage:
```bash
./run-load-test.sh --targets "http://my-service:8080" --watch
```

Using the included sample HTTP server:
```bash
./run-load-test.sh --targets "http://http-server" --watch
```

Full options:
```bash
./run-load-test.sh [options]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-n, --name NAME` | Name for the test job | auto-generated |
| `-t, --targets URLS` | Comma-separated target service URLs | http://http-server |
| `--low-vus NUM` | Number of VUs for low traffic tier | 10 |
| `--medium-vus NUM` | Number of VUs for medium traffic tier | 50 |
| `--high-vus NUM` | Number of VUs for high traffic tier | 100 |
| `--peak-vus NUM` | Number of VUs for peak traffic tier | 200 |
| `-d, --duration MINUTES` | Duration for each traffic tier in minutes | 5 |
| `--namespace NAMESPACE` | Kubernetes namespace to create the job in | default |
| `--watch` | Watch the job progress after creation | - |
| `--deployment-name NAME` | Name of the deployment to monitor | edgedelta |
| `--deployment-ns NAMESPACE` | Namespace of the deployment to monitor | edgedelta |
| `-h, --help` | Show help message | - |

### Load Test Pattern

The load test follows a four-phase pattern:

1. **Low Traffic**: Runs with a small number of virtual users
2. **Medium Traffic**: Increases load to a moderate level
3. **High Traffic**: Runs with a significant load
4. **Peak Traffic**: Ramps up to maximum load and then back down

Each phase runs for the specified duration (default: 5 minutes).

## Report Generation

The utility automatically generates an HTML report with:

- Resource usage metrics (CPU, memory)
- Traffic performance metrics
- Visualizations of resource usage across different load tiers

### Accessing Reports

After a test completes, you can access the report by:

```bash
# Find the pod name
kubectl -n NAMESPACE get pods --selector=job-name=JOB_NAME

# Copy the report to your local machine
kubectl -n NAMESPACE cp POD_NAME:results/test-TIMESTAMP/report.html ./report.html -c report-generator
```

### S3 and Slack Integration

If AWS credentials and a Slack webhook URL are provided in the `load-test-credentials` secret, the utility will:

1. Upload the report to S3
2. Post a notification to Slack with a link to the report

## Files Included

- `run-load-test.sh` - Main script to run load tests
- `bench.yaml` - Kubernetes job template for load testing
- `setup-load-test-prereqs.sh` - Script to set up required permissions
- `http-server.yaml` - Optional sample HTTP server for testing

## Customization

### Template Customization

You can modify the `bench.yaml` template to customize the load test behavior. The template uses the following placeholders:

- `{{TEST_NAME}}`: Name of the load test job
- `{{NAMESPACE}}`: Kubernetes namespace
- `{{DEPLOYMENT_NAME}}`: Name of the deployment to monitor
- `{{DEPLOYMENT_NAMESPACE}}`: Namespace of the deployment to monitor
- `{{DURATION_MINUTES}}`: Duration of each load tier in minutes
- `{{LOW_VUS}}`: Virtual users for low traffic tier
- `{{MEDIUM_VUS}}`: Virtual users for medium traffic tier
- `{{HIGH_VUS}}`: Virtual users for high traffic tier
- `{{PEAK_VUS}}`: Virtual users for peak traffic tier
- `{{TARGET_SERVICES}}`: Target service URLs for load testing

### K6 Script Customization

To customize the load testing behavior, edit the K6 script section in the template.

## Troubleshooting

### Common Issues

1. **Service account not found:**
   ```
   Error: Required service account 'load-test-sa' not found in namespace 'NAMESPACE'
   ```
   Run the setup script to create the service account:
   ```bash
   ./setup-load-test-prereqs.sh NAMESPACE
   ```

2. **Pod stuck in pending state:**
   Check for resource constraints in the namespace:
   ```bash
   kubectl describe pod POD_NAME -n NAMESPACE
   ```

### Viewing Logs

To view logs from the load test containers:

```bash
# Resource monitor logs
kubectl logs POD_NAME -c resource-monitor -n NAMESPACE

# K6 load tester logs
kubectl logs POD_NAME -c k6-load-tester -n NAMESPACE

# Report generator logs
kubectl logs POD_NAME -c report-generator -n NAMESPACE
```

## Cleanup

### Removing Load Test Jobs

To delete completed load test jobs:

```bash
# Delete a specific job
kubectl delete job JOB_NAME -n NAMESPACE

# Delete all load test jobs
kubectl delete jobs -l app=load-test -n NAMESPACE
```

### Removing Credentials

If you want to remove the stored credentials:

```bash
kubectl delete secret load-test-credentials -n NAMESPACE
```

### Removing Service Account and Permissions

To completely remove the load test framework permissions:

```bash
kubectl delete serviceaccount load-test-sa -n NAMESPACE
kubectl delete rolebinding load-test-rb -n NAMESPACE
kubectl delete role load-test-role -n NAMESPACE
```

### Removing the Sample HTTP Server

If you deployed the included sample HTTP server:

```bash
kubectl delete -f http-server.yaml
```

## Running Tests on Different Nodes

By default, multiple load test jobs may run on the same node. To distribute tests across different nodes in your cluster, you can add pod anti-affinity to your `bench.yaml` template:

```yaml
# Add this under spec.template.spec section
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - load-test
        topologyKey: "kubernetes.io/hostname"
```

This configuration will attempt to schedule load test pods on different nodes when multiple tests are running simultaneously.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

The MIT License is a permissive license that allows for reuse with few restrictions. It permits use, modification, distribution, and private use while only requiring license and copyright notice preservation.