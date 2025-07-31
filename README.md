
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
```

Make sure you have the HF key available

```bash
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
RESULT_FILE=$(oc exec -n bench -c sidecar "$POD" -- sh -c 'ls -1 /output/results-*.json | head -n1')
RESULT_FILENAME=$(basename "$RESULT_FILE")
LOG_FILENAME="${RESULT_FILENAME%.json}-logs.txt"

oc logs $POD -n bench -c benchmark
oc exec -n bench -c sidecar $POD -- ls -ltahR /output/

oc cp "bench/${POD}:${RESULT_FILE}" "./$(basename "$RESULT_FILE")" -c sidecar
oc logs "$POD" -n bench -c benchmark > "$LOG_FILENAME"

echo "- Logs saved to: $LOG_FILENAME"
echo "- Results saved to: $RESULT_FILENAME"
```

This will give you both the json output and the logs locally,
now you can work on your results

## Debugging

```bash
kubectl get pods,svc -n istio-system
kubectl get pods,gateway -n llm-d
kubectl get pods,gateway -n llm-d-monitoring
```
