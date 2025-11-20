# Test Fixtures

This directory contains test fixtures for testing the Wozz audit script.

## Usage

### Test on Minikube

```bash
# Start minikube
minikube start

# Deploy test workloads
kubectl apply -f test-fixtures/sample-workload.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=test-nginx --timeout=60s

# Run audit
cd ..
./scripts/wozz-audit.sh

# Verify output
ls -la wozz-audit-*.tar.gz
tar -tzf wozz-audit-*.tar.gz
```

### Test on Kind

```bash
# Create kind cluster
kind create cluster --name wozz-test

# Deploy test workloads
kubectl apply -f test-fixtures/sample-workload.yaml

# Run audit
cd ..
./scripts/wozz-audit.sh

# Cleanup
kind delete cluster --name wozz-test
```

## Test Scenarios

### Scenario 1: Over-Provisioned Resources
The `sample-workload.yaml` includes:
- Memory limit 4x higher than request (1024Mi vs 256Mi)
- CPU limit 5x higher than request (500m vs 100m)

**Expected Finding:** Over-provisioned memory/CPU detected

### Scenario 2: Missing Resource Requests
The `test-no-requests` deployment has no resource requests/limits.

**Expected Finding:** Missing requests warning

## Expected Audit Output

After running the audit, you should see:
- `pods-anonymized.json` with test workloads
- `summary.json` showing 3 pods total
- `usage-pods.txt` (if metrics-server installed)

## Cleanup

```bash
# Remove test workloads
kubectl delete -f test-fixtures/sample-workload.yaml

# Remove audit output
rm -rf wozz-audit-*
```


