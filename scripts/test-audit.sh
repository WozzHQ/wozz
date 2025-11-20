#!/bin/bash
# test-audit.sh - Comprehensive test suite for wozz-audit.sh
# Run this before launching to production

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🧪 Wozz Audit Test Suite"
echo "=========================="
echo ""

TESTS_PASSED=0
TESTS_FAILED=0
CRITICAL_FAILURE=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    echo -n "Testing: $test_name... "
    
    if eval "$test_command" > /dev/null 2>&1; then
        if [ "$expected_result" = "pass" ]; then
            echo -e "${GREEN}✓ PASS${NC}"
            ((TESTS_PASSED++))
            return 0
        else
            echo -e "${RED}✗ FAIL (expected to fail)${NC}"
            ((TESTS_FAILED++))
            return 1
        fi
    else
        if [ "$expected_result" = "fail" ]; then
            echo -e "${GREEN}✓ PASS (failed as expected)${NC}"
            ((TESTS_PASSED++))
            return 0
        else
            echo -e "${RED}✗ FAIL${NC}"
            ((TESTS_FAILED++))
            return 1
        fi
    fi
}

# Test 1: Check prerequisites
echo "Phase 1: Prerequisites"
echo "----------------------"
run_test "kubectl installed" "command -v kubectl" "pass"
run_test "python3 installed" "command -v python3" "pass"
run_test "tar installed" "command -v tar" "pass"
run_test "jq installed" "command -v jq" "pass" || echo "  (jq optional but recommended)"
echo ""

# Test 2: Syntax validation
echo "Phase 2: Syntax Validation"
echo "--------------------------"
run_test "Bash syntax valid" "bash -n scripts/wozz-audit.sh" "pass"
run_test "Python syntax valid" "python3 -m py_compile scripts/analyze-audit.py" "pass"
echo ""

# Test 3: File permissions
echo "Phase 3: File Permissions"
echo "-------------------------"
run_test "wozz-audit.sh is executable" "test -x scripts/wozz-audit.sh" "pass"
run_test "analyze-audit.py is executable" "test -x scripts/analyze-audit.py" "pass"
echo ""

# Test 4: Check for cluster connectivity (optional)
echo "Phase 4: Cluster Connectivity (Optional)"
echo "----------------------------------------"
if kubectl cluster-info > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Kubernetes cluster accessible${NC}"
    CLUSTER_AVAILABLE=true
    
    echo ""
    echo "  Connected to: $(kubectl config current-context)"
    echo ""
    
    # Test 5: Run actual audit
    echo "Phase 5: Running Actual Audit"
    echo "-----------------------------"
    echo "  This will create a real audit output..."
    echo ""
    
    if ./scripts/wozz-audit.sh; then
        echo -e "${GREEN}✓ Audit script completed successfully${NC}"
        ((TESTS_PASSED++))
        
        # Find the created tarball
        TARBALL=$(ls -t wozz-audit-*.tar.gz 2>/dev/null | head -1)
        
        if [ -f "$TARBALL" ]; then
            echo -e "${GREEN}✓ Tarball created: $TARBALL${NC}"
            ((TESTS_PASSED++))
            
            # Test 6: Verify tarball contents
            echo ""
            echo "Phase 6: Tarball Verification"
            echo "------------------------------"
            
            # Extract to temp directory
            TEMP_DIR=$(mktemp -d)
            tar -xzf "$TARBALL" -C "$TEMP_DIR"
            
            AUDIT_DIR=$(find "$TEMP_DIR" -type d -name "wozz-audit-*" | head -1)
            
            # Check for required files
            run_test "pods-anonymized.json exists" "test -f $AUDIT_DIR/pods-anonymized.json" "pass"
            run_test "summary.json exists" "test -f $AUDIT_DIR/summary.json" "pass"
            run_test "README.txt exists" "test -f $AUDIT_DIR/README.txt" "pass"
            
            # Test 7: Anonymization verification (CRITICAL)
            echo ""
            echo "Phase 7: Anonymization Verification (CRITICAL)"
            echo "----------------------------------------------"
            
            if [ -f "$AUDIT_DIR/pods-anonymized.json" ]; then
                # Check for plain-text names (should NOT exist)
                if grep -qi "test-nginx" "$AUDIT_DIR/pods-anonymized.json" 2>/dev/null; then
                    echo -e "${RED}✗ CRITICAL: Plain-text names found in anonymized file!${NC}"
                    echo "  Names were NOT properly anonymized!"
                    CRITICAL_FAILURE=1
                    ((TESTS_FAILED++))
                else
                    echo -e "${GREEN}✓ No plain-text names found${NC}"
                    ((TESTS_PASSED++))
                fi
                
                # Check for hashed values (should exist)
                if grep -qE "[a-f0-9]{12}" "$AUDIT_DIR/pods-anonymized.json" 2>/dev/null; then
                    echo -e "${GREEN}✓ Hashed values present${NC}"
                    ((TESTS_PASSED++))
                else
                    echo -e "${YELLOW}⚠ Warning: No hashed values found (might be empty cluster)${NC}"
                fi
                
                # Verify JSON is valid
                if python3 -c "import json; json.load(open('$AUDIT_DIR/pods-anonymized.json'))" 2>/dev/null; then
                    echo -e "${GREEN}✓ JSON structure is valid${NC}"
                    ((TESTS_PASSED++))
                else
                    echo -e "${RED}✗ JSON structure is invalid${NC}"
                    ((TESTS_FAILED++))
                fi
            fi
            
            # Test 8: Analysis script
            echo ""
            echo "Phase 8: Analysis Script Test"
            echo "------------------------------"
            
            if python3 scripts/analyze-audit.py "$AUDIT_DIR" > /tmp/wozz-analysis-output.txt 2>&1; then
                echo -e "${GREEN}✓ Analysis script ran successfully${NC}"
                ((TESTS_PASSED++))
                
                # Show preview of output
                echo ""
                echo "  Analysis output preview:"
                echo "  ------------------------"
                head -10 /tmp/wozz-analysis-output.txt | sed 's/^/  /'
                echo ""
            else
                echo -e "${RED}✗ Analysis script failed${NC}"
                ((TESTS_FAILED++))
            fi
            
            # Cleanup
            rm -rf "$TEMP_DIR"
            
        else
            echo -e "${RED}✗ Tarball was not created${NC}"
            CRITICAL_FAILURE=1
            ((TESTS_FAILED++))
        fi
    else
        echo -e "${RED}✗ Audit script failed${NC}"
        CRITICAL_FAILURE=1
        ((TESTS_FAILED++))
    fi
    
else
    echo -e "${YELLOW}⚠ No Kubernetes cluster available${NC}"
    echo "  To test with a real cluster:"
    echo "    minikube start"
    echo "    kubectl apply -f test-fixtures/sample-workload.yaml"
    echo "    ./scripts/test-audit.sh"
    echo ""
fi

# Summary
echo ""
echo "================================"
echo "Test Results Summary"
echo "================================"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $CRITICAL_FAILURE -eq 1 ]; then
    echo -e "${RED}🚨 CRITICAL FAILURE DETECTED${NC}"
    echo "   Do NOT launch until this is fixed!"
    echo ""
    exit 1
elif [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${YELLOW}⚠ Some tests failed${NC}"
    echo "  Review failures before launching"
    echo ""
    exit 1
else
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo "  Ready for launch (pending manual verification)"
    echo ""
    exit 0
fi


