
# Instructions

The dockerfile in this repo is built and served in:

```
FROM ghcr.io/ccamacho/bench:latest
```

## Testing the bench container

```bash
oc new-project bench
```

We make sure we cleanup the environment first

```bash
# Begin Cleanup
oc delete job -n bench -l job-name=guidellm-benchmark --ignore-not-found
oc get pods -n bench --no-headers | grep guidellm-benchmark | awk '{print $1}' | xargs -r -n1 oc delete pod -n bench
oc delete secret hf-token-secret -n bench --ignore-not-found
# End Cleanup

# Make sure you have the HF key available

oc create secret generic hf-token-secret \
  --from-file=token=$HOME/.keys/hf.key \
  -n bench
```

Note: Make sure to update
`--target http://llm-d-inference-gateway-istio.llm-d.svc.cluster.local \`
with the actual endpoint you are testing in `guidellm-job.yml`.

VLLM_HOST=$(oc get route vllm -n my-vllm-runtime -o jsonpath='{.spec.host}')

curl http://$VLLM_HOST/health

Now let's run the job and fetch the results.

```bash
# Deploy the job
oc apply -f guidellm-job.yml

oc get job -n bench guidellm-benchmark

# Fetch the status and results
oc get pods -n bench | grep guidellm-benchmark
POD=$(oc get pods -n bench --no-headers | grep guidellm-benchmark | awk '{print $1}')

oc logs $POD -n bench -c benchmark
oc logs $POD -n bench -c dcgm-metrics-scraper
oc exec -n bench -c sidecar $POD -- ls -ltahR /output/

# Get the timestamp from any results file to ensure we get matching pairs
TIMESTAMP=$(oc exec -n bench -c sidecar "$POD" -- sh -c 'ls -1 /output/results-*.json | head -n1' | sed 's/.*results-guidellm-\(.*\)\.json/\1/')

GUIDELLM_BENCHMARK_FILE="results-guidellm-${TIMESTAMP}.json"
GUIDELLM_LOG_FILENAME="results-guidellmlogs-${TIMESTAMP}.txt"
DCGM_OUTPUT_FILE="results-dcgm-${TIMESTAMP}.txt"

# Copy both result files
oc cp "bench/${POD}:/output/${GUIDELLM_BENCHMARK_FILE}" "./${GUIDELLM_BENCHMARK_FILE}" -c sidecar
oc cp "bench/${POD}:/output/${DCGM_OUTPUT_FILE}" "./${DCGM_OUTPUT_FILE}" -c sidecar
oc logs "$POD" -n bench -c benchmark > "$GUIDELLM_LOG_FILENAME"

echo "- Guidellm Logs saved to: $GUIDELLM_LOG_FILENAME"
echo "- Guidellm Results saved to: $GUIDELLM_BENCHMARK_FILE"
echo "- NDCGM Results saved to: $DCGM_OUTPUT_FILE"
```

This will give you both the json output and the logs locally,
now you can work on your results

## Debugging

```bash
kubectl get pods,svc -n istio-system
kubectl get pods,gateway -n llm-d
kubectl get pods,gateway -n llm-d-monitoring
```

# GPU Usage Plotting Script

A Python script to visualize GPU usage metrics from DCGM (Data Center GPU Manager) data files in Prometheus format.

## Features

- Parse DCGM metrics from Prometheus format files
- Plot GPU utilization, power usage, temperature, and memory utilization over time
- Support for multiple GPUs and hosts
- Interactive HTML plots using Plotly
- Combined dashboard view or individual metric plots
- Summary statistics for all metrics

## Installation

1. Install the required Python packages:
```bash
pip3 install -r requirements.txt
```

## Usage

### Basic Usage

Plot all GPU metrics in a combined dashboard:
```bash
python3 gpu_plot.py results-dcgm-20250731-092704.txt
```

### Specific Metrics

Plot only GPU utilization:
```bash
python3 gpu_plot.py results-dcgm-20250731-092704.txt --metric util
```

Plot only power usage:
```bash
python3 gpu_plot.py results-dcgm-20250731-092704.txt --metric power
```

Plot only temperature:
```bash
python3 gpu_plot.py results-dcgm-20250731-092704.txt --metric temp
```

Plot only memory utilization:
```bash
python3 gpu_plot.py results-dcgm-20250731-092704.txt --metric memory
```

### Custom Output

Specify a custom output file:
```bash
python3 gpu_plot.py results-dcgm-20250731-092704.txt --output my_gpu_metrics.html
```

## Data Format

The script expects DCGM metrics in Prometheus format with the following metrics:

- `DCGM_FI_DEV_GPU_UTIL`: GPU utilization (%)
- `DCGM_FI_DEV_POWER_USAGE`: Power usage (W)
- `DCGM_FI_DEV_GPU_TEMP`: GPU temperature (°C)
- `DCGM_FI_DEV_MEM_COPY_UTIL`: Memory utilization (%)

Example data format:
```
DCGM_FI_DEV_GPU_UTIL{gpu="0",UUID="GPU-7bec0fc5...",device="nvidia0",modelName="NVIDIA L40S"} 85.5
DCGM_FI_DEV_POWER_USAGE{gpu="0",UUID="GPU-7bec0fc5...",device="nvidia0",modelName="NVIDIA L40S"} 245.2
```

## Output

The script generates an interactive HTML file with:

- Time series plots for each metric
- Multiple GPUs shown with different colors
- Hover information with detailed values
- Summary statistics printed to console

## Examples

1. **Monitor GPU utilization during a benchmark:**
   ```bash
   python3 gpu_plot.py benchmark_gpu_data.txt --metric util -o utilization_report.html
   ```

2. **Generate a complete GPU health dashboard:**
   ```bash
   python3 gpu_plot.py monitoring_data.txt --metric all -o gpu_dashboard.html
   ```

3. **Check power consumption patterns:**
   ```bash
   python3 gpu_plot.py power_monitoring.txt --metric power -o power_analysis.html
   ```

## Dependencies

- Python 3.6+
- plotly: Interactive plotting library
- pandas: Data manipulation
- numpy: Numerical operations
- kaleido: Static image export (optional)

## Similar to bench-plot

This script follows the same design patterns as the `bench-plot` script but is specifically tailored for GPU monitoring data:

- Uses Plotly for interactive visualizations
- Supports command-line arguments for different plot types
- Generates HTML output for easy sharing
- Provides summary statistics
- Handles multiple data series (GPUs) with distinct styling
