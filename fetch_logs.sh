#!/bin/bash
set -e

# Namespaces
NAMESPACE="llm-d-inference-scheduling"
BENCH_NAMESPACE="bench"

# Output configuration
OUTPUT_DIR="./logs-$(date +%Y%m%d-%H%M%S)"

BENCHMARK_JOB="guidellm-benchmark"
EPP_POD=""
EPP_NODE_NAME=""
EPP_POD_UID=""
BENCHMARK_POD=""
TIMESTAMP=""

GUIDELLM_MULTITURN_FILE=""
THANOS_METRICS_FILE=""
AVAILABLE_METRICS_FILE=""
ALL_METRICS_FILE=""
GUIDELLM_LOG_FILENAME=""
EPP_LOG_FILENAME=""

mkdir -p "$OUTPUT_DIR"

# Find benchmark pod
BENCHMARK_POD=$(oc get pods -n $BENCH_NAMESPACE --no-headers | grep $BENCHMARK_JOB | awk '{print $1}')

if [ -z "$BENCHMARK_POD" ]; then
    echo "ERROR: Could not find benchmark pod"
    echo "Available pods in $BENCH_NAMESPACE:"
    oc get pods -n $BENCH_NAMESPACE
    exit 1
fi

# Find EPP pod
EPP_POD=$(oc get pods -n $NAMESPACE -l inferencepool=gaie-inference-scheduling-epp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$EPP_POD" ]; then
    echo "ERROR: No EPP pod found with label 'inferencepool=gaie-inference-scheduling-epp'"
    echo "Available pods in $NAMESPACE:"
    oc get pods -n $NAMESPACE
    exit 1
fi

# Get node and UID for EPP pod
EPP_NODE_NAME=$(oc get pod $EPP_POD -n $NAMESPACE -o jsonpath='{.spec.nodeName}')
EPP_POD_UID=$(oc get pod $EPP_POD -n $NAMESPACE -o jsonpath='{.metadata.uid}')

if [ -z "$EPP_NODE_NAME" ] || [ -z "$EPP_POD_UID" ]; then
    echo "ERROR: Could not get node name or UID for EPP pod $EPP_POD"
    exit 1
fi

echo "Found EPP pod: $EPP_POD"
echo "Running on node: $EPP_NODE_NAME"
echo "Pod UID: $EPP_POD_UID"
echo ""

echo "Benchmark execution logs:"
oc logs $BENCHMARK_POD -n $BENCH_NAMESPACE -c benchmark --tail=10

echo ""
echo "Thanos scraper logs:"
oc logs $BENCHMARK_POD -n $BENCH_NAMESPACE -c thanos-metrics-scraper --tail=5

echo ""
echo "Available output files:"
oc exec -n $BENCH_NAMESPACE -c sidecar $BENCHMARK_POD -- ls -ltahR /output/

# Get timestamp from results files
TIMESTAMP=$(oc exec -n $BENCH_NAMESPACE -c sidecar "$BENCHMARK_POD" -- sh -c 'ls -1 /output/results-*.json | head -n1' | sed 's/.*results-[^-]*-\(.*\)\.json/\1/')

if [ -z "$TIMESTAMP" ]; then
    echo "ERROR: Could not extract timestamp from benchmark results"
    exit 1
fi


# Set file names
GUIDELLM_MULTITURN_FILE="results-guidellm-${TIMESTAMP}.json"
THANOS_METRICS_FILE="results-thanos-${TIMESTAMP}.json"
AVAILABLE_METRICS_FILE="available-vllm-metrics-${TIMESTAMP}.txt"
ALL_METRICS_FILE="all-metrics-response-${TIMESTAMP}.json"
GUIDELLM_LOG_FILENAME="results-guidellmlogs-${TIMESTAMP}.txt"
EPP_LOG_FILENAME="epp-logs-benchmark-${TIMESTAMP}.log"


# Extract benchmark start/end times from Thanos metrics
BENCHMARK_START=$(oc exec -n $BENCH_NAMESPACE -c sidecar "$BENCHMARK_POD" -- grep -o '"benchmark_start":"[^"]*"' "/output/$THANOS_METRICS_FILE" | cut -d'"' -f4)
BENCHMARK_END=$(oc exec -n $BENCH_NAMESPACE -c sidecar "$BENCHMARK_POD" -- grep -o '"benchmark_end":"[^"]*"' "/output/$THANOS_METRICS_FILE" | cut -d'"' -f4)

if [ -z "$BENCHMARK_START" ] || [ -z "$BENCHMARK_END" ]; then
    echo "WARNING: Could not extract benchmark timeframe, using full EPP logs"
    EPP_FILTER_CMD="oc logs deployment/gaie-inference-scheduling-epp -n $NAMESPACE --timestamps=true"
else
    echo "Benchmark timeframe: $BENCHMARK_START to $BENCHMARK_END"
    EPP_FILTER_CMD="oc logs deployment/gaie-inference-scheduling-epp -n $NAMESPACE --timestamps=true | awk -v start=\"${BENCHMARK_START%.*}\" -v end=\"${BENCHMARK_END%.*}\" '\$1 >= start && \$1 <= end'"
fi


echo "Copying GuideLlm results..."
oc cp "$BENCH_NAMESPACE/${BENCHMARK_POD}:/output/${GUIDELLM_MULTITURN_FILE}" "$OUTPUT_DIR/${GUIDELLM_MULTITURN_FILE}" -c sidecar || echo "WARNING: GuideLL-M results not found"

# Copy Thanos metrics
echo "Copying Thanos metrics..."
oc cp "$BENCH_NAMESPACE/${BENCHMARK_POD}:/output/${THANOS_METRICS_FILE}" "$OUTPUT_DIR/${THANOS_METRICS_FILE}" -c sidecar

# Copy available metrics list
echo "Copying available metrics list..."
oc cp "$BENCH_NAMESPACE/${BENCHMARK_POD}:/output/${AVAILABLE_METRICS_FILE}" "$OUTPUT_DIR/${AVAILABLE_METRICS_FILE}" -c sidecar

# Copy all metrics response
echo "Copying all metrics response..."
oc cp "$BENCH_NAMESPACE/${BENCHMARK_POD}:/output/${ALL_METRICS_FILE}" "$OUTPUT_DIR/${ALL_METRICS_FILE}" -c sidecar

# Extract benchmark execution logs
echo "Extracting benchmark execution logs..."
oc logs "$BENCHMARK_POD" -n $BENCH_NAMESPACE -c benchmark > "$OUTPUT_DIR/$GUIDELLM_LOG_FILENAME"


eval $EPP_FILTER_CMD > "$OUTPUT_DIR/$EPP_LOG_FILENAME"


LOG_BASE_PATH="/host/var/log/pods/${NAMESPACE}_${EPP_POD}_${EPP_POD_UID}/epp"

LOG_FILES=$(oc debug node/$EPP_NODE_NAME -- ls -la $LOG_BASE_PATH 2>/dev/null || echo "")

if [ ! -z "$LOG_FILES" ]; then
    echo "Additional EPP log files found:"
    echo "$LOG_FILES"
    echo ""
    
    # Extract current log file (0.log)
    if oc debug node/$EPP_NODE_NAME -- test -f $LOG_BASE_PATH/0.log 2>/dev/null; then
        echo "Extracting current EPP log..."
        oc debug node/$EPP_NODE_NAME -- cat $LOG_BASE_PATH/0.log > "$OUTPUT_DIR/epp-current-complete.log" 2>/dev/null
        echo "Extracted: epp-current-complete.log ($(du -h "$OUTPUT_DIR/epp-current-complete.log" | cut -f1))"
    fi
    
    # Extract rotated log files
    ROTATED_LOGS=$(oc debug node/$EPP_NODE_NAME -- ls $LOG_BASE_PATH/ 2>/dev/null | grep "^0\.log\." | grep -v "\.gz$" || echo "")
    for rotated_log in $ROTATED_LOGS; do
        if [ ! -z "$rotated_log" ]; then
            echo "Extracting rotated EPP log ($rotated_log)..."
            safe_name=$(echo $rotated_log | sed 's/0\.log\./rotated-/' | tr ':' '-')
            oc debug node/$EPP_NODE_NAME -- cat $LOG_BASE_PATH/$rotated_log > "$OUTPUT_DIR/epp-$safe_name.log" 2>/dev/null
            echo "Extracted: epp-$safe_name.log ($(du -h "$OUTPUT_DIR/epp-$safe_name.log" | cut -f1))"
        fi
    done
    
    # Extract compressed log files
    COMPRESSED_LOGS=$(oc debug node/$EPP_NODE_NAME -- ls $LOG_BASE_PATH/ 2>/dev/null | grep "\.gz$" || echo "")
    for compressed_log in $COMPRESSED_LOGS; do
        if [ ! -z "$compressed_log" ]; then
            echo "Extracting compressed EPP log ($compressed_log)..."
            safe_name=$(echo $compressed_log | sed 's/0\.log\./compressed-/' | sed 's/\.gz$//' | tr ':' '-')
            oc debug node/$EPP_NODE_NAME -- cat $LOG_BASE_PATH/$compressed_log > "$OUTPUT_DIR/epp-$safe_name.log.gz" 2>/dev/null
            gunzip -f "$OUTPUT_DIR/epp-$safe_name.log.gz"
            echo "Extracted: epp-$safe_name.log ($(du -h "$OUTPUT_DIR/epp-$safe_name.log" | cut -f1))"
        fi
    done
    
    echo "Complete EPP log history extracted!"
else
    echo "No additional EPP log files accessible (using benchmark-period logs only)"
fi

cd "$OUTPUT_DIR"

# Validate all JSON files
json_valid=0
json_total=0

for json_file in *.json; do
    if [ -f "$json_file" ]; then
        json_total=$((json_total + 1))
        if jq empty "$json_file" >/dev/null 2>&1; then
            echo "✅ $json_file (valid JSON structure)"
            json_valid=$((json_valid + 1))
        else
            echo "❌ $json_file (INVALID JSON structure)"
        fi
    fi
done
