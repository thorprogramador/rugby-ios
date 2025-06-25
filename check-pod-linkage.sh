#!/bin/bash

# check-pod-linkage.sh
# Script to check if pods are linked as source code or binary

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if a pod is linked as source or binary
check_pod_linkage() {
    local pod_name="$1"
    local pods_project="${2:-Pods/Pods.xcodeproj/project.pbxproj}"
    local rugby_bin_dir="${3:-.rugby/bin}"
    
    # Check if pod target exists in Pods project
    if grep -q "name = $pod_name;" "$pods_project" 2>/dev/null; then
        # Pod is in project - check if it's a test target
        if grep -q "name = $pod_name.*\.xctest" "$pods_project" 2>/dev/null; then
            echo -e "${BLUE}🧪 $pod_name${NC} - Test target (SOURCE)"
        else
            echo -e "${GREEN}✅ $pod_name${NC} - Linked as SOURCE"
        fi
        
        # Additional check: look for the target's source files
        local file_count=$(grep -c "/* $pod_name/" "$pods_project" 2>/dev/null || echo "0")
        if [ "$file_count" -gt 0 ] 2>/dev/null; then
            echo "   └─ Found $file_count file references in project"
        fi
    else
        # Pod not in project - check if binaries exist
        local binary_found=false
        
        # Check in .rugby/bin directory
        if [ -d "$rugby_bin_dir/$pod_name" ]; then
            binary_found=true
            echo -e "${YELLOW}📦 $pod_name${NC} - Linked as BINARY"
            
            # Show available binary configurations
            local configs=$(ls -1 "$rugby_bin_dir/$pod_name" 2>/dev/null | head -3)
            if [ -n "$configs" ]; then
                echo "   └─ Binary configurations available:"
                echo "$configs" | while read -r config; do
                    echo "      • $config"
                done
            fi
        else
            # Also check in .rugby/build directory
            local rugby_base_dir=$(dirname "$rugby_bin_dir")
            local build_binary=$(find "$rugby_base_dir/build" -name "lib${pod_name}.a" -o -name "${pod_name}.framework" 2>/dev/null | head -1)
            
            if [ -n "$build_binary" ]; then
                binary_found=true
                echo -e "${YELLOW}📦 $pod_name${NC} - Linked as BINARY"
                echo "   └─ Binary location: ${build_binary#$rugby_base_dir/}"
            fi
        fi
        
        if [ "$binary_found" = false ]; then
            echo -e "${RED}❓ $pod_name${NC} - NOT FOUND (not in project, no binaries)"
        fi
    fi
}

# Function to check all pods
check_all_pods() {
    local pods_project="${1:-Pods/Pods.xcodeproj/project.pbxproj}"
    
    echo "🔍 Scanning all pods in project..."
    echo ""
    
    # Extract all unique pod names from the project
    local all_pods=$(grep -o 'name = [^;]*;' "$pods_project" 2>/dev/null | \
                     sed 's/name = //;s/;//' | \
                     grep -v '\.xctest$' | \
                     grep -v '^Pods-' | \
                     grep -v '^AppHost-' | \
                     sort -u)
    
    local source_count=0
    local binary_count=0
    
    while IFS= read -r pod; do
        if [ -n "$pod" ]; then
            result=$(check_pod_linkage "$pod" "$pods_project")
            echo "$result"
            
            if [[ "$result" == *"SOURCE"* ]]; then
                ((source_count++))
            elif [[ "$result" == *"BINARY"* ]]; then
                ((binary_count++))
            fi
        fi
    done <<< "$all_pods"
    
    echo ""
    echo "📊 Summary:"
    echo "   • Source pods: $source_count"
    echo "   • Binary pods: $binary_count"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [POD_NAME...]"
    echo ""
    echo "Check if CocoaPods are linked as source code or binary"
    echo ""
    echo "Options:"
    echo "  -a, --all          Check all pods in the project"
    echo "  -p, --project PATH Path to Pods.xcodeproj/project.pbxproj (default: Pods/Pods.xcodeproj/project.pbxproj)"
    echo "  -b, --bin-dir PATH Path to Rugby binary directory (default: .rugby/bin)"
    echo "  -r, --root PATH    iOS project root directory (will look for Pods/Pods.xcodeproj inside)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 Alamofire"
    echo "  $0 NavigationMocks PayMocks ProfileRenderers"
    echo "  $0 --all"
    echo "  $0 --project /path/to/Pods/Pods.xcodeproj/project.pbxproj Alamofire"
    echo "  $0 --root /path/to/ios-project ProfileRenderers"
}

# Main script
main() {
    local check_all=false
    local pods_project="Pods/Pods.xcodeproj/project.pbxproj"
    local rugby_bin_dir=".rugby/bin"
    local pod_names=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                check_all=true
                shift
                ;;
            -p|--project)
                pods_project="$2"
                shift 2
                ;;
            -b|--bin-dir)
                rugby_bin_dir="$2"
                shift 2
                ;;
            -r|--root)
                pods_project="$2/Pods/Pods.xcodeproj/project.pbxproj"
                rugby_bin_dir="$2/.rugby/bin"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                pod_names+=("$1")
                shift
                ;;
        esac
    done
    
    # Check if Pods project exists
    if [ ! -f "$pods_project" ]; then
        echo -e "${RED}Error: Pods project not found at: $pods_project${NC}"
        echo "Make sure you're in the iOS project root directory and have run 'pod install'"
        exit 1
    fi
    
    # Check if Rugby is being used
    if grep -q "RUGBY_PATCHED" "$pods_project" 2>/dev/null; then
        echo -e "${BLUE}🏈 Rugby is currently active in this project${NC}"
        echo ""
    fi
    
    # Execute based on options
    if [ "$check_all" = true ]; then
        check_all_pods "$pods_project"
    elif [ ${#pod_names[@]} -eq 0 ]; then
        echo "Error: No pod names specified"
        echo ""
        show_usage
        exit 1
    else
        # Check specific pods
        for pod_name in "${pod_names[@]}"; do
            check_pod_linkage "$pod_name" "$pods_project" "$rugby_bin_dir"
        done
    fi
}

# Run main function
main "$@"