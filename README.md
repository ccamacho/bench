
# Instructions

The dockerfile in this repo is built and served in:

```
FROM ghcr.io/ccamacho/bench:latest
```

## Testing the bench container

```bash
oc create project llm-d
```

We make sure we cleanup the environment first

```bash
# Begin Cleanup
oc delete job -n llm-d -l job-name=guidellm-benchmark --ignore-not-found
oc get pods -n llm-d --no-headers | grep guidellm-benchmark | awk '{print $1}' | xargs -r -n1 oc delete pod -n llm-d
oc delete secret hf-token-secret -n llm-d --ignore-not-found
# End Cleanup
```

Make sure you have the HF key available

```bash
oc create secret generic hf-token-secret \
  --from-file=token=$HOME/.keys/hf.key \
  -n llm-d
```

Note: Make sure to update
`--target http://llm-d-inference-gateway-istio.llm-d.svc.cluster.local \`
with the actual endpoint you are testing in guidellm-job.yml.

```
# Deploy the job
oc apply -f guidellm-job.yml

oc get job -n llm-d guidellm-benchmark

# Fetch the status and results
oc get pods -n llm-d | grep guidellm-benchmark
POD=$(oc get pods -n llm-d --no-headers | grep guidellm-benchmark | awk '{print $1}')

oc logs $POD -n llm-d -c benchmark
oc exec -n llm-d -c sidecar $POD -- ls -ltahR /output/

RESULT_FILE=$(oc exec -n llm-d -c sidecar "$POD" -- sh -c 'ls -1 /output/results-*.json | head -n1')

oc cp "llm-d/${POD}:${RESULT_FILE}" "./$(basename "$RESULT_FILE")" -c sidecar

```

This will give you a file like results-TS.json locally,
now you can work on your results

## Debugging

```bash
kubectl get pods,svc -n istio-system
kubectl get pods,gateway -n llm-d
kubectl get pods,gateway -n llm-d-monitoring
```
