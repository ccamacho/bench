

```bash
kubectl get pods,svc -n istio-system
kubectl get pods,gateway -n llm-d
kubectl get pods,gateway -n llm-d-monitoring

```



```
# Begin Cleanup
oc delete job -n llm-d -l job-name=guidellm-benchmark --ignore-not-found
oc get pods -n llm-d --no-headers | grep guidellm-benchmark | awk '{print $1}' | xargs -r -n1 oc delete pod -n llm-d
oc delete secret hf-token-secret -n llm-d --ignore-not-found
# End Cleanup


# Make sure you have the HF key available
oc create secret generic hf-token-secret \
  --from-file=token=$HOME/.keys/hf.key \
  -n llm-d

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
