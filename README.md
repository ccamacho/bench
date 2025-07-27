
```
# Cleanup
oc delete job -n llm-d -l job-name=guidellm-benchmark --ignore-not-found
oc get pods -n llm-d --no-headers | grep guidellm-benchmark | awk '{print $1}' | xargs -r -n1 oc delete pod -n llm-d

# Make sure you have the HF key available
oc delete secret hf-token-secret -n llm-d --ignore-not-found
oc create secret generic hf-token-secret \
  --from-file=token=$HOME/.keys/hf.key \
  -n llm-d

# Deploy the job
oc apply -f guidellm-job.yml

# Fetch the status and results
oc get pods -n llm-d | grep guidellm-benchmark
POD=$(oc get pods -n llm-d --no-headers | grep guidellm-benchmark | awk '{print $1}')
oc logs $POD -n llm-d -c benchmark
oc exec -n llm-d -c sidecar $POD -- ls -lh /

oc cp llm-d/$POD:/output/results.json ./results.json -c sidecar
```
