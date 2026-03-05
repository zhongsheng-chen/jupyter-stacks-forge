#!/usr/bin/env bash
set -euo pipefail

# ========================================
# build.sh - Jupyter foundation image builder
# Based on official Jupyter Docker Stack
#
# Usage:
#   ./build.sh [OPTIONS] [--build-arg KEY=VALUE ...]
#
# Options:
#   --image NAME          Docker image name (default: zhongsheng/docker-stacks-foundation)
#   --tag TAG             Docker image tag (default: latest)
#   --owner OWNER         Docker Hub owner/username (default: zhongsheng)
#   --registry REG        Docker registry (default: docker.io)
#   --no-cache            Disable Docker build cache
#   --log-dir DIR         Directory to store log files (default: logs/)
#   --verbose             Enable verbose output
#   --cleanup             Clean up old images after build
#   --push                Push image to registry after build
#   --build-arg KV        Pass build arguments to Docker (can be used multiple times)
#   -h, --help            Show this help message
#
# Examples:
#   ./build.sh                                                           # default build
#   ./build.sh --tag python-3.11 --no-cache                              # custom tag with no cache
#   ./build.sh --owner myuser --push                                     # build and push
#   ./build.sh --build-arg BASE_IMAGE=quay.io/jupyter/docker-stacks-foundation
#   ./build.sh --build-arg BASE_TAG=latest
#   ./build.sh --build-arg PYTHON_VERSION=3.12
# ========================================

# ===== 全局配置 =====
readonly DEFAULT_IMAGE_NAME="docker-stacks-foundation"
readonly DEFAULT_OWNER="zhongsheng"
readonly DEFAULT_TAG="latest"
readonly DEFAULT_REGISTRY="docker.io"
readonly DEFAULT_LOG_DIR="logs/"
readonly SCRIPT_NAME="$(basename "$0")"
readonly TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
readonly DOCKERFILE="Dockerfile"
readonly MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB

# ===== 颜色配置 =====
if [[ -t 1 ]] && [[ "$TERM" != "dumb" ]]; then
    readonly COLOR_RESET="\033[0m"
    readonly COLOR_RED="\033[0;31m"
    readonly COLOR_GREEN="\033[0;32m"
    readonly COLOR_YELLOW="\033[0;33m"
    readonly COLOR_BLUE="\033[0;34m"
    readonly COLOR_CYAN="\033[0;36m"
    readonly COLOR_BOLD="\033[1m"
    readonly COLOR_DIM="\033[2m"
else
    readonly COLOR_RESET=""
    readonly COLOR_RED=""
    readonly COLOR_GREEN=""
    readonly COLOR_YELLOW=""
    readonly COLOR_BLUE=""
    readonly COLOR_CYAN=""
    readonly COLOR_BOLD=""
    readonly COLOR_DIM=""
fi

# ===== 全局变量 =====
IMAGE_NAME="$DEFAULT_IMAGE_NAME"
IMAGE_TAG="$DEFAULT_TAG"
NO_CACHE=false
LOG_DIR="$DEFAULT_LOG_DIR"
LOG_FILE=""
VERBOSE=false
CLEANUP=false
PUSH=false
REGISTRY="$DEFAULT_REGISTRY"
OWNER="$DEFAULT_OWNER"
BUILD_PID=""                  # 用于跟踪构建进程的 PID
EXIT_CODE=0                   # 记录退出码
BUILD_START_TIME=""           # 构建开始时间
BUILD_ARGS=()                 # 存储 build args 的数组

# ===== 日志函数 =====
log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $*"
    if [[ -n "$LOG_FILE" ]]; then
        printf "[INFO] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true
    fi
    return 0
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2
    if [[ -n "$LOG_FILE" ]]; then
        printf "[ERROR] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true
    fi
    return 0
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $*"
    if [[ -n "$LOG_FILE" ]]; then
        printf "[SUCCESS] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true
    fi
    return 0
}

log_warning() {
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $*"
    if [[ -n "$LOG_FILE" ]]; then
        printf "[WARNING] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true
    fi
    return 0
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${COLOR_DIM}[DEBUG]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $*"
        if [[ -n "$LOG_FILE" ]]; then
            printf "[DEBUG] %s - %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true
        fi
    fi
    return 0
}

# ===== 帮助函数 =====
show_help() {
    echo -e "${COLOR_BOLD}Usage:${COLOR_RESET}"
    echo -e "  $0 [OPTIONS] [--build-arg KEY=VALUE ...]"
    echo
    echo -e "${COLOR_BOLD}Options:${COLOR_RESET}"
    echo -e "  --image NAME          Docker image name (default: ${COLOR_CYAN}${DEFAULT_IMAGE_NAME}${COLOR_RESET})"
    echo -e "  --tag TAG             Docker image tag (default: ${COLOR_CYAN}${DEFAULT_TAG}${COLOR_RESET})"
    echo -e "  --owner OWNER         Docker Hub owner/username (default: ${COLOR_CYAN}${DEFAULT_OWNER}${COLOR_RESET})"
    echo -e "  --registry REG        Docker registry (default: ${COLOR_CYAN}${DEFAULT_REGISTRY}${COLOR_RESET})"
    echo -e "  --no-cache            Disable Docker build cache"
    echo -e "  --log-dir DIR         Directory to store log files (default: ${COLOR_CYAN}${DEFAULT_LOG_DIR}${COLOR_RESET})"
    echo -e "  --verbose             Enable verbose output"
    echo -e "  --push                Push image to registry after build"
    echo -e "  --build-arg KV        Pass build arguments to Docker (can be used multiple times)"
    echo -e "  -h, --help            Show this help message"
    echo
    echo -e "${COLOR_BOLD}Examples:${COLOR_RESET}"
    echo -e "  $0                                                           # default: ${DEFAULT_REGISTRY}/${DEFAULT_OWNER}/${DEFAULT_IMAGE_NAME}:${DEFAULT_TAG}"
    echo -e "  $0 --owner myuser --tag v1.0.0                               # myuser/${DEFAULT_IMAGE_NAME}:v1.0.0"
    echo -e "  $0 --image custom-notebook --tag python-3.11                 # ${DEFAULT_OWNER}/custom-notebook:python-3.11"
    echo -e "  $0 --registry myregistry.com:5000 --owner team --push        # push to private registry"
    echo -e "  $0 --no-cache --verbose                                      # build with no cache and debug output"
    echo -e "  $0 --build-arg REGISTRY=myregistry --build-arg OWNER=myuser  # custom base image registry"

    # 直接退出，不触发 trap
    trap - EXIT INT TERM
    exit 0
}

# ===== 环境检查 =====
check_environment() {
    log_debug "Checking environment..."
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon not running"
        exit 1
    fi
    
    # 检查 Dockerfile
    if [[ ! -f "$DOCKERFILE" ]]; then
        log_error "$DOCKERFILE not found"
        exit 1
    fi
    
    # 检查必要的文件
    local required_files=(
        "fix-permissions"
        "initial-condarc"
        "run-hooks.sh"
        "start.sh"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_warning "Required file not found: $file"
        fi
    done
    
    # 检查磁盘空间
    local available_space
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS
        available_space=$(df -g . | awk 'NR==2 {print $4}' | sed 's/G//')
    else
        # Linux
        available_space=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    fi
    
    if [[ ${available_space%.*} -lt 10 ]]; then
        log_warning "Low disk space: ${available_space}GB available. At least 10GB recommended for this build."
    fi

    # 检查日志目录
    if [[ "$LOG_DIR" == "logs" && ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || log_warning "Could not create logs directory"
    fi
    
    log_debug "Environment check passed"
}

# ===== 退出处理函数 =====
handle_exit() {
    local exit_code=$EXIT_CODE
    
    # 如果 EXIT_CODE 没有设置，使用实际的退出码
    if [[ $exit_code -eq 0 ]]; then
        exit_code=$?
    fi
    
    log_debug "Handling exit with code: $exit_code"
    
    # 清理构建进程（如果还在运行）
    if [[ -n "$BUILD_PID" ]] && kill -0 "$BUILD_PID" 2>/dev/null; then
        log_warning "Cleaning up build process (PID: $BUILD_PID)"
        kill -TERM "$BUILD_PID" 2>/dev/null || true
        sleep 1
        if kill -0 "$BUILD_PID" 2>/dev/null; then
            log_warning "Build process still running, forcing kill..."
            kill -KILL "$BUILD_PID" 2>/dev/null || true
        fi
    fi
    
    # 计算构建时间
    if [[ -n "$BUILD_START_TIME" ]]; then
        local end_time=$(date +%s)
        local duration=$((end_time - BUILD_START_TIME))
        local minutes=$((duration / 60))
        local seconds=$((duration % 60))
        log_info "Total build time: ${minutes}m ${seconds}s"
    fi
    
    # 写入日志结束标记
    if [[ -n "$LOG_FILE" ]]; then
        {
            echo ""
            echo "=========================================="
            echo "Build process ended at: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Exit code: $exit_code"
            echo "=========================================="
        } >> "$LOG_FILE"
    fi
    
    # 根据退出码输出最终状态
    case $exit_code in
        0)
            log_success "Build completed successfully"
            ;;
        130)
            log_error "Build interrupted by user (Ctrl+C)"
            ;;
        143)
            log_error "Build terminated by SIGTERM"
            ;;
        *)
            if [[ $exit_code -ne 0 ]]; then
                log_error "Build failed with exit code: $exit_code"
            fi
            ;;
    esac
    
    exit $exit_code
}

# ===== 信号处理函数 =====
handle_signal() {
    local signal=$1
    local exit_code=$2
    
    echo  # 换行
    log_warning "Received $signal signal"
    
    # 设置退出码
    EXIT_CODE=$exit_code
    
    # 如果有构建进程，先尝试优雅终止
    if [[ -n "$BUILD_PID" ]] && kill -0 "$BUILD_PID" 2>/dev/null; then
        log_info "Forwarding $signal to build process (PID: $BUILD_PID)"
        kill -"${signal#SIG}" "$BUILD_PID" 2>/dev/null || true
        
        # 给进程一些时间清理
        sleep 2
        
        # 如果进程还在，强制终止
        if kill -0 "$BUILD_PID" 2>/dev/null; then
            log_warning "Build process did not respond to $signal, forcing kill..."
            kill -KILL "$BUILD_PID" 2>/dev/null || true
        fi
    fi
    
    # 调用退出处理
    handle_exit
}

# ===== 参数解析 =====
parse_arguments() {
    # 初始化变量（使用默认值）
    IMAGE_NAME="$DEFAULT_IMAGE_NAME"
    IMAGE_TAG="$DEFAULT_TAG"
    NO_CACHE=false
    LOG_DIR="$DEFAULT_LOG_DIR"
    VERBOSE=false
    CLEANUP=false
    PUSH=false
    REGISTRY="$DEFAULT_REGISTRY"
    OWNER="$DEFAULT_OWNER"
    
    # 标志位：记录用户是否指定了完整镜像名
    local user_specified_full_image=false
    local user_specified_image=false
    local user_specified_owner=false
    local user_specified_tag=false
    
    # 清空 BUILD_ARGS 数组
    BUILD_ARGS=()
    
    # 遍历所有参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --image)
                if [[ -n "${2:-}" ]]; then
                    # 检查是否包含斜杠（即是否已经包含了owner）
                    if [[ "$2" == */* ]]; then
                        IMAGE_NAME="$2"
                        user_specified_full_image=true
                        user_specified_image=true
                        log_debug "User specified full image name: $IMAGE_NAME (includes owner)"
                    else
                        # 临时保存镜像名，稍后在构建完整名称时使用
                        IMAGE_NAME_TEMP="$2"
                        user_specified_image=true
                        log_debug "User specified image name (without owner): $IMAGE_NAME_TEMP"
                    fi
                    shift 2
                else
                    log_error "--image requires an image name"
                    EXIT_CODE=1
                    exit 1
                fi
                ;;
            --owner)
                if [[ -n "${2:-}" ]]; then
                    OWNER="$2"
                    user_specified_owner=true
                    log_debug "User specified owner: $OWNER"
                    shift 2
                else
                    log_error "--owner requires an owner name"
                    EXIT_CODE=1
                    exit 1
                fi
                ;;
            --tag)
                if [[ -n "${2:-}" ]]; then
                    IMAGE_TAG="$2"
                    user_specified_tag=true 
                    log_debug "User specified tag: $IMAGE_TAG"
                    shift 2
                else
                    log_error "--tag requires a tag value"
                    EXIT_CODE=1
                    exit 1
                fi
                ;;
            --no-cache)
                NO_CACHE=true
                log_debug "Cache disabled"
                shift
                ;;
            --log-dir)
                if [[ -n "${2:-}" ]]; then
                    LOG_DIR="$2"
                    log_debug "User specified log directory: $LOG_DIR"
                    shift 2
                else
                    log_error "--log-dir requires a directory path"
                    EXIT_CODE=1
                    exit 1
                fi
                ;;
            --verbose)
                VERBOSE=true
                log_debug "Verbose mode enabled"
                shift
                ;;
            --cleanup)
                CLEANUP=true
                log_debug "Cleanup enabled"
                shift
                ;;
            --push)
                PUSH=true
                log_debug "Push to registry enabled"
                shift
                ;;
            --registry)
                if [[ -n "${2:-}" ]]; then
                    REGISTRY="$2"
                    log_debug "User specified registry: $REGISTRY"
                    shift 2
                else
                    log_error "--registry requires a registry address"
                    EXIT_CODE=1
                    exit 1
                fi
                ;;
            --build-arg)
                if [[ -n "${2:-}" ]]; then
                    # 验证格式是否为 KEY=VALUE
                    if [[ "$2" =~ ^[A-Za-z0-9_]+=.*$ ]]; then
                        BUILD_ARGS+=("--build-arg" "$2")
                        log_debug "Build arg added: $2"
                        shift 2
                    else
                        log_error "--build-arg requires KEY=VALUE format, got: $2"
                        EXIT_CODE=1
                        exit 1
                    fi
                else
                    log_error "--build-arg requires a value"
                    EXIT_CODE=1
                    exit 1
                fi
                ;;
            -h|--help)
                show_help
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                ;;
            *)
                log_error "Unexpected argument: $1 (use --image and --tag options instead)"
                show_help
                ;;
        esac
    done
    
    # 构建最终的镜像名称
    if [[ "$user_specified_full_image" == true ]]; then
        # 用户指定了完整的镜像名，直接使用
        if [[ "$user_specified_tag" == true ]]; then
            log_info "Using user-specified full image name: $IMAGE_NAME with user-specified tag: $IMAGE_TAG"
        else
            log_info "Using user-specified full image name: $IMAGE_NAME with default tag: $DEFAULT_TAG"
        fi
    elif [[ "$user_specified_image" == true ]] && [[ -n "${IMAGE_NAME_TEMP:-}" ]]; then
        # 用户指定了镜像名（不含owner），结合owner构建
        IMAGE_NAME="${OWNER}/${IMAGE_NAME_TEMP}"
        if [[ "$user_specified_owner" == true ]]; then
            if [[ "$user_specified_tag" == true ]]; then
                log_info "Combining user-specified owner ($OWNER) and image name ($IMAGE_NAME_TEMP) with user-specified tag ($IMAGE_TAG) -> $IMAGE_NAME:$IMAGE_TAG"
            else
                log_info "Combining user-specified owner ($OWNER) and image name ($IMAGE_NAME_TEMP) with default tag ($DEFAULT_TAG) -> $IMAGE_NAME:$DEFAULT_TAG"
            fi
        else
            if [[ "$user_specified_tag" == true ]]; then
                log_info "Using default owner ($DEFAULT_OWNER) with user-specified image name ($IMAGE_NAME_TEMP) and user-specified tag ($IMAGE_TAG) -> $IMAGE_NAME:$IMAGE_TAG"
            else
                log_info "Using default owner ($DEFAULT_OWNER) with user-specified image name ($IMAGE_NAME_TEMP) and default tag ($DEFAULT_TAG) -> $IMAGE_NAME:$DEFAULT_TAG"
            fi
        fi
    elif [[ "$user_specified_owner" == true ]]; then
        # 用户只指定了owner，使用默认镜像名但应用owner
        IMAGE_NAME="${OWNER}/${DEFAULT_IMAGE_NAME}"
        if [[ "$user_specified_tag" == true ]]; then
            log_info "Using user-specified owner ($OWNER) with default image name ($DEFAULT_IMAGE_NAME) and user-specified tag ($IMAGE_TAG) -> $IMAGE_NAME:$IMAGE_TAG"
        else
            log_info "Using user-specified owner ($OWNER) with default image name ($DEFAULT_IMAGE_NAME) and default tag ($DEFAULT_TAG) -> $IMAGE_NAME:$DEFAULT_TAG"
        fi
    else
        # 完全使用默认值
        IMAGE_NAME="${DEFAULT_OWNER}/${DEFAULT_IMAGE_NAME}"
        if [[ "$user_specified_tag" == true ]]; then
            log_info "Using default values: owner=$DEFAULT_OWNER, image=$DEFAULT_IMAGE_NAME with user-specified tag=$IMAGE_TAG -> $IMAGE_NAME:$IMAGE_TAG"
        else
            log_info "Using default values: owner=$DEFAULT_OWNER, image=$DEFAULT_IMAGE_NAME, tag=$DEFAULT_TAG -> $IMAGE_NAME:$DEFAULT_TAG"
        fi
    fi

    # 确认函数执行完成
    log_debug "parse_arguments completed successfully"
    return 0
}

# ===== 参数验证 =====
validate_arguments() {
    # 验证镜像名称格式
    if [[ ! "$IMAGE_NAME" =~ ^[a-zA-Z0-9./_-]+$ ]]; then
        log_error "Invalid image name format: $IMAGE_NAME"
        log_error "Image name can only contain letters, numbers, dots, slashes, underscores, and hyphens"
        EXIT_CODE=1
        exit 1
    fi
    
    # 验证镜像标签格式
    if [[ ! "$IMAGE_TAG" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        log_error "Invalid image tag format: $IMAGE_TAG"
        log_error "Image tag can only contain letters, numbers, dots, underscores, and hyphens"
        EXIT_CODE=1
        exit 1
    fi
    
    # 验证 registry 格式（如果提供）
    if [[ -n "$REGISTRY" ]]; then
        # 简单的 registry 格式验证
        if [[ ! "$REGISTRY" =~ ^[a-zA-Z0-9.-]+(:[0-9]+)?$ ]] && \
           [[ ! "$REGISTRY" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?$ ]]; then
            log_warning "Registry format may be invalid: $REGISTRY"
            log_warning "Expected format: hostname[:port] or IP:port"
        fi
    fi
    
    # 验证并创建日志目录
    if [[ -n "$LOG_DIR" ]]; then
        # 使用 realpath 获取规范化路径（如果可用）
        if command -v realpath &>/dev/null; then
            # 创建目录（如果不存在）
            mkdir -p "$LOG_DIR" 2>/dev/null || {
                log_error "Failed to create log directory: $LOG_DIR"
                EXIT_CODE=1
                exit 1
            }
            # 获取规范化的绝对路径
            LOG_DIR="$(realpath "$LOG_DIR")"
            log_debug "Normalized log directory (realpath): $LOG_DIR"
        else
            # 降级方案：清理末尾斜杠并尝试获取绝对路径
            # 移除末尾所有斜杠
            LOG_DIR_CLEAN="${LOG_DIR%%/}"
            # 如果清理后为空（即输入是 "/"），则设为根目录
            if [[ -z "$LOG_DIR_CLEAN" ]]; then
                LOG_DIR_CLEAN="/"
            fi
            
            # 创建目录（如果不存在）
            mkdir -p "$LOG_DIR_CLEAN" 2>/dev/null || {
                log_error "Failed to create log directory: $LOG_DIR_CLEAN"
                EXIT_CODE=1
                exit 1
            }
            
            # 尝试获取绝对路径
            if [[ "$LOG_DIR_CLEAN" = /* ]]; then
                # 已经是绝对路径，直接使用
                LOG_DIR="$LOG_DIR_CLEAN"
            else
                # 相对路径，转换为绝对路径
                LOG_DIR="$(cd "$LOG_DIR_CLEAN" 2>/dev/null && pwd || echo "$LOG_DIR_CLEAN")"
            fi
            log_debug "Normalized log directory (fallback): $LOG_DIR"
        fi
        
        # 设置日志文件路径
        LOG_FILE="${LOG_DIR}/build_${IMAGE_NAME//\//_}_${IMAGE_TAG}_${TIMESTAMP}.log"
        log_debug "Log file will be created at: $LOG_FILE"
        
        # 创建日志文件并写入初始信息
        touch "$LOG_FILE" || {
            log_error "Failed to create log file: $LOG_FILE"
            EXIT_CODE=1
            exit 1
        }
        
        # 写入日志头信息
        {
            echo "=========================================="
            echo "Jupyter Image Builder"
            echo "Script: $SCRIPT_NAME"
            echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "Output image: ${IMAGE_NAME}:${IMAGE_TAG}"
            if [[ -n "$REGISTRY" ]]; then
                echo "Registry: $REGISTRY"
            else
                echo "Registry: Docker Hub (default)"
            fi
            if [[ ${#BUILD_ARGS[@]} -gt 0 ]]; then
                echo "Build args: ${BUILD_ARGS[*]}"
            fi
            echo "Log Directory: $LOG_DIR"
            echo "Log File: $LOG_FILE"
            echo "=========================================="
            echo ""
        } >> "$LOG_FILE"
    fi
}

# ===== 设置日志轮转 =====
setup_log_rotation() {
    if [[ -n "$LOG_FILE" ]] && [[ -f "$LOG_FILE" ]]; then
        local log_size
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS
            log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
        else
            # Linux
            log_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        fi
        
        if [[ $log_size -gt $MAX_LOG_SIZE ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.old"
            log_info "Previous log file archived to ${LOG_FILE}.old"
            
            # 重新创建日志文件
            touch "$LOG_FILE"
        fi
    fi
}

# ===== 获取基础镜像信息 =====
get_base_image() {
    local base_image="library/ubuntu"
    local base_tag="24.04"
    
    # 从 BUILD_ARGS 中查找 BASE_IMAGE 和 BASE_TAG
    local i=0
    while [[ $i -lt ${#BUILD_ARGS[@]} ]]; do
        if [[ "${BUILD_ARGS[$i]}" == "--build-arg" ]]; then
            local arg="${BUILD_ARGS[$((i+1))]}"
            case "$arg" in
                BASE_IMAGE=*)
                    base_image="${arg#BASE_IMAGE=}"
                    # 调试信息直接输出到 stderr，避免被捕获
                    log_debug "Found BASE_IMAGE: $base_image" >&2
                    ;;
                BASE_TAG=*)
                    base_tag="${arg#BASE_TAG=}"
                    log_debug "Found BASE_TAG: $base_tag" >&2
                    ;;
            esac
        fi
        i=$((i + 2))
    done
    
    # 只输出最终结果到 stdout
    echo "${base_image}:${base_tag}"
}

# ===== 自动生成镜像名称和标签 =====
generate_image_and_tag() {
    # 如果用户已经通过 --image 或 --tag 指定了，则不自动生成
    local user_specified_image=false
    local user_specified_tag=false
    
    if [[ "$IMAGE_NAME" != "$DEFAULT_IMAGE_NAME" ]]; then
        user_specified_image=true
    fi
    
    if [[ "$IMAGE_TAG" != "$DEFAULT_TAG" ]]; then
        user_specified_tag=true
    fi
    
    # 调用 get_base_image 获取完整的基础镜像信息
    local base_image_full
    base_image_full=$(get_base_image)
    
    # 分离 BASE_IMAGE 和 BASE_TAG
    local base_image="${base_image_full%:*}"
    local base_tag="${base_image_full#*:}"
    
    log_debug "Base image: $base_image"
    log_debug "Base tag: $base_tag"
    
    # 检查是否通过 --build-arg 指定了 BASE_IMAGE
    local base_image_specified=false
    local base_tag_specified=false
    
    local i=0
    while [[ $i -lt ${#BUILD_ARGS[@]} ]]; do
        if [[ "${BUILD_ARGS[$i]}" == "--build-arg" ]]; then
            local arg="${BUILD_ARGS[$((i+1))]}"
            case "$arg" in
                BASE_IMAGE=*)
                    base_image_specified=true
                    log_debug "BASE_IMAGE was specified via --build-arg"
                    ;;
                BASE_TAG=*)
                    base_tag_specified=true
                    log_debug "BASE_TAG was specified via --build-arg"
                    ;;
            esac
        fi
        i=$((i + 2))
    done
    
    # 如果通过 --build-arg 指定了 BASE_IMAGE 且用户没有指定 --image，则自动生成镜像名称
    if [[ "$base_image_specified" == true ]] && [[ "$user_specified_image" == false ]]; then
        local base_name
        base_name=$(basename "$base_image" | cut -d':' -f1)
        IMAGE_NAME="${OWNER}/${base_name}"
        log_info "Auto-generated image name: $IMAGE_NAME (from BASE_IMAGE=$base_image)"
    fi
    
    # 如果通过 --build-arg 指定了 BASE_TAG 且用户没有指定 --tag，则自动生成标签
    if [[ "$base_tag_specified" == true ]] && [[ "$user_specified_tag" == false ]]; then
        IMAGE_TAG="$base_tag"
        log_info "Auto-generated image tag: $IMAGE_TAG (from BASE_TAG=$base_tag)"
    fi

    log_debug "generate_image_and_tag completed"
}

# ===== 构建镜像 =====
build_image() {
    local full_image="${IMAGE_NAME}:${IMAGE_TAG}"
    local build_cmd="docker build"
    
    log_info "Starting build process"
    log_info "Building image: $full_image"
    
    # 获取基础镜像信息
    local base_image
    base_image=$(get_base_image)
    log_info "Base image: $base_image"
    
    # 构建命令参数
    if [[ "$NO_CACHE" == true ]]; then
        build_cmd="$build_cmd --no-cache --pull"
        log_info "Build cache: disabled (will pull latest base image)"
    else
        build_cmd="$build_cmd --pull"
        log_info "Build cache: enabled (will pull latest base image)"
    fi
    
    # 添加 build args
    if [[ ${#BUILD_ARGS[@]} -gt 0 ]]; then
        build_cmd="$build_cmd ${BUILD_ARGS[*]}"
        log_info "Build arguments: ${COLOR_CYAN}${BUILD_ARGS[*]}${COLOR_RESET}"
    fi
    
    build_cmd="$build_cmd -t $full_image ."
    log_debug "Build command: $build_cmd"
    
    # 显示构建信息
    echo -e "\n${COLOR_BOLD}${COLOR_CYAN}════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}🚀 Building Jupyter image${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}Base image:${COLOR_RESET} $base_image"
    echo -e "${COLOR_BOLD}Output image:${COLOR_RESET} $full_image"
    
    if [[ -n "$REGISTRY" ]]; then
        echo -e "${COLOR_BOLD}Registry:${COLOR_RESET} $REGISTRY"
    else
        echo -e "${COLOR_BOLD}Registry:${COLOR_RESET} Docker Hub (default)"
    fi
    
    echo -e "${COLOR_BOLD}Cache:${COLOR_RESET} $([[ "$NO_CACHE" == true ]] && echo "Disabled" || echo "Enabled")"
    
    if [[ ${#BUILD_ARGS[@]} -gt 0 ]]; then
        echo -e "${COLOR_BOLD}Build args:${COLOR_RESET} ${BUILD_ARGS[*]}"
    fi
    
    echo -e "${COLOR_BOLD}Log file:${COLOR_RESET} ${LOG_FILE:-'No logging'}"
    echo -e "${COLOR_BOLD}Start time:${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}════════════════════════════════════════${COLOR_RESET}\n"
    
    # 创建一个临时文件来捕获Docker输出
    local temp_output
    temp_output=$(mktemp)
    
    # 在后台运行构建命令，将输出重定向到临时文件
    (
        # 设置子shell的信号处理
        trap 'exit 130' INT
        trap 'exit 143' TERM
        
        if [[ "$VERBOSE" == true ]]; then
            # 详细模式：直接显示所有输出
            eval "$build_cmd" 2>&1 | tee "$temp_output"
        else
            # 非详细模式：只捕获输出到文件，不显示
            eval "$build_cmd" > "$temp_output" 2>&1
        fi
    ) &
    BUILD_PID=$!
    
    log_debug "Build process started with PID: $BUILD_PID"
    
    # 显示构建进度（如果非verbose模式）
    if [[ "$VERBOSE" == false ]]; then
        local stages=(
            "📦 Preparing build context"
            "⚙️  Executing Dockerfile instructions"
            "📥 Downloading base image layers"
            "🔧 Installing system dependencies"
            "🐍 Setting up Python environment"
            "📚 Installing Python packages"
            "🗄️  Installing database clients"
            "🧹 Cleaning up cache"
            "✅ Finalizing image"
        )
        
        local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0
        local start_time=$(date +%s)
        local stage_index=0
        local last_check_time=$start_time
        local last_output_size=0
        
        # 保存光标位置
        echo -ne "\033[s"
        
        while kill -0 $BUILD_PID 2>/dev/null; do
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            local minutes=$((elapsed / 60))
            local seconds=$((elapsed % 60))
            
            # 每5秒检查一次输出文件，尝试推断当前阶段
            if [[ $((current_time - last_check_time)) -ge 5 ]] && [[ -f "$temp_output" ]]; then
                local current_size=$(stat -c%s "$temp_output" 2>/dev/null || echo 0)
                
                # 如果输出在增长，说明正在处理
                if [[ $current_size -gt $last_output_size ]]; then
                    # 根据输出内容判断阶段
                    if grep -q "Downloading\|Pulling" "$temp_output" 2>/dev/null; then
                        stage_index=2  # 下载阶段
                    elif grep -q "build-essential\|gcc\|apt-get" "$temp_output" 2>/dev/null; then
                        stage_index=3  # 系统依赖安装
                    elif grep -q "pip\|python setup" "$temp_output" 2>/dev/null; then
                        stage_index=5  # Python包安装
                    elif grep -q "Successfully built" "$temp_output" 2>/dev/null; then
                        stage_index=8  # 完成阶段
                    fi
                    
                    last_output_size=$current_size
                fi
                last_check_time=$current_time
            fi
            
            # 恢复光标位置并更新显示
            echo -ne "\033[u"
            printf "${COLOR_CYAN}%s${COLOR_RESET} ${COLOR_BOLD}[%02d:%02d]${COLOR_RESET} %s" \
                "${spinner[i]}" "$minutes" "$seconds" "${stages[$stage_index]}"
            
            i=$(( (i+1) % 10 ))
            sleep 0.2
        done
        
        # 清除进度显示
        echo -ne "\033[u\033[K"
        
        # 如果构建成功完成，显示完成信息
        if wait $BUILD_PID 2>/dev/null; then
            echo -e "${COLOR_GREEN}✅ Build completed!${COLOR_RESET} $(date '+%H:%M:%S')"
        fi
    fi
    
    # 等待构建完成并获取退出码
    wait $BUILD_PID
    local build_exit_code=$?
    BUILD_PID=""  # 清除PID，表示构建已完成

    # 如果构建失败且非verbose模式，显示错误输出
    if [[ $build_exit_code -ne 0 ]] && [[ "$VERBOSE" == false ]] && [[ -f "$temp_output" ]]; then
        echo -e "\n${COLOR_RED}❌ Build failed. Last few lines of output:${COLOR_RESET}"
        echo -e "${COLOR_DIM}════════════════════════════════════════${COLOR_RESET}"
        tail -n 20 "$temp_output" | sed "s/^/  /"
        echo -e "${COLOR_DIM}════════════════════════════════════════${COLOR_RESET}"
        echo -e "For complete logs, check: ${COLOR_CYAN}$LOG_FILE${COLOR_RESET} or run with --verbose"
    fi
    
    # 将临时文件内容追加到日志文件
    if [[ -n "$LOG_FILE" ]] && [[ -f "$temp_output" ]]; then
        cat "$temp_output" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"
    fi
    
    # 清理临时文件
    rm -f "$temp_output"
    
    if [[ $build_exit_code -eq 0 ]]; then
        log_success "Docker build completed successfully"
        return 0
    else
        if [[ $build_exit_code -eq 130 ]]; then
            log_error "Docker build was interrupted by user"
            EXIT_CODE=130
        elif [[ $build_exit_code -eq 143 ]]; then
            log_error "Docker build was terminated"
            EXIT_CODE=143
        else
            log_error "Docker build failed with exit code: $build_exit_code"
            EXIT_CODE=$build_exit_code
        fi
        return $build_exit_code
    fi
}

# ===== 验证镜像 =====
verify_image() {
    local full_image="${IMAGE_NAME}:${IMAGE_TAG}"
    
    log_info "Verifying image: $full_image"
    echo -e "\n${COLOR_BOLD}🔍 Verifying image...${COLOR_RESET}"
    
    # 验证 Python
    echo -e "\n${COLOR_BOLD}🐍 Checking Python...${COLOR_RESET}"
    
    # 检查 Python 版本
    if timeout 10s docker run --rm --entrypoint python "$full_image" --version; then
        log_success "Python is available"
    else
        # 尝试直接运行 bash
        if timeout 10s docker run --rm --entrypoint bash "$full_image" -c "python --version"; then
            log_success "Python is available (via bash)"
        else
            # 最后尝试检查文件系统
            if timeout 10s docker run --rm --entrypoint ls "$full_image" -la /opt/conda/bin/; then
                log_warning "Python may be available but cannot be executed directly"
            else
                log_error "Cannot verify Python in image!"
                EXIT_CODE=1
                return 1
            fi
        fi
    fi
    
    # 获取镜像大小
    echo -e "\n${COLOR_BOLD}📦 Image details:${COLOR_RESET}"
    local image_size
    image_size=$(docker image inspect "$full_image" --format '{{.Size}}')
    echo -e "Size: $((image_size / 1024 / 1024)) MB"
    log_info "Image size: $((image_size / 1024 / 1024)) MB"
    
    return 0
}

# ===== 推送镜像 =====
push_image() {
    if [[ "$PUSH" != true ]]; then
        return 0
    fi
    
    local full_image="${IMAGE_NAME}:${IMAGE_TAG}"
    local push_image=""
    
    # 构建推送地址
    if [[ -n "$REGISTRY" ]] && [[ "$REGISTRY" != "docker.io" ]]; then
        push_image="${REGISTRY}/${full_image}"
    else
        push_image="$full_image"
    fi
    
    log_info "Pushing image to registry: $push_image"
    echo -e "\n${COLOR_BOLD}📤 Pushing image to registry...${COLOR_RESET}"
    
    # 如果推送地址与本地标签不同，需要先打标签
    if [[ "$push_image" != "$full_image" ]]; then
        log_debug "Tagging image: $full_image -> $push_image"
        if ! docker tag "$full_image" "$push_image"; then
            log_error "Failed to tag image: $full_image -> $push_image"
            EXIT_CODE=1
            return 1
        fi
    fi
    
    # 推送镜像
    echo -e "Pushing to: ${COLOR_CYAN}${push_image}${COLOR_RESET}"
    if docker push "$push_image"; then
        log_success "Image pushed successfully: $push_image"
        echo -e "${COLOR_GREEN}✅ Push completed${COLOR_RESET}"
    else
        log_error "Failed to push image: $push_image"
        EXIT_CODE=1
        return 1
    fi
    
    return 0
}

# ===== 清理旧镜像 =====
cleanup_old_images() {
    if [[ "$CLEANUP" != true ]]; then
        return 0
    fi
    
    log_info "Cleaning up old images..."
    echo -e "\n${COLOR_BOLD}🧹 Cleaning up old images...${COLOR_RESET}"
    
    # 显示当前磁盘使用情况
    echo -e "\n${COLOR_DIM}Before cleanup:${COLOR_RESET}"
    docker system df
    
    # 清理 dangling 镜像
    local dangling_count
    dangling_count=$(docker images -f "dangling=true" -q | wc -l)
    if [[ $dangling_count -gt 0 ]]; then
        log_info "Removing $dangling_count dangling images..."
        docker image prune -f || true
    fi
    
    # 清理构建缓存
    log_info "Cleaning build cache..."
    docker builder prune -f || true
    
    # 显示清理后磁盘使用情况
    echo -e "\n${COLOR_DIM}After cleanup:${COLOR_RESET}"
    docker system df
    
    log_success "Cleanup completed"
}

# ===== 显示构建摘要 =====
show_build_summary() {
    local full_image="${IMAGE_NAME}:${IMAGE_TAG}"
    local push_image=""
    
    if [[ -n "$REGISTRY" ]] && [[ "$REGISTRY" != "docker.io" ]] && [[ "$PUSH" == true ]]; then
        push_image="${REGISTRY}/${full_image}"
    elif [[ "$PUSH" == true ]]; then
        push_image="$full_image"
    fi
    
    echo -e "\n${COLOR_BOLD}${COLOR_GREEN}════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_GREEN}✓ Build Summary${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_GREEN}════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}Image:${COLOR_RESET} $full_image"
    echo -e "${COLOR_BOLD}Registry:${COLOR_RESET} $REGISTRY"
    echo -e "${COLOR_BOLD}Owner:${COLOR_RESET} $OWNER"
    
    # 获取镜像详细信息
    local image_id image_size image_created
    image_id=$(docker image inspect "$full_image" --format '{{.Id}}' | cut -d: -f2 | cut -c1-12)
    image_size=$(docker image inspect "$full_image" --format '{{.Size}}')
    image_created=$(docker image inspect "$full_image" --format '{{.Created}}' | cut -dT -f1)
    
    echo -e "${COLOR_BOLD}ID:${COLOR_RESET} $image_id"
    echo -e "${COLOR_BOLD}Size:${COLOR_RESET} $((image_size / 1024 / 1024)) MB"
    echo -e "${COLOR_BOLD}Created:${COLOR_RESET} $image_created"
    
    if [[ "$PUSH" == true ]]; then
        echo -e "${COLOR_BOLD}Pushed to:${COLOR_RESET} ${push_image:-$full_image}"
    fi
    
    if [[ ${#BUILD_ARGS[@]} -gt 0 ]]; then
        echo -e "${COLOR_BOLD}Build args used:${COLOR_RESET}"
        for ((i=0; i<${#BUILD_ARGS[@]}; i+=2)); do
            echo -e "  ${BUILD_ARGS[i+1]}"
        done
    fi
    
    echo -e "${COLOR_BOLD}${COLOR_GREEN}════════════════════════════════════════${COLOR_RESET}"
}

# ===== 主函数 =====
main() {
    # 记录开始时间
    BUILD_START_TIME=$(date +%s)

    # 设置信号处理
    trap 'handle_signal SIGINT 130' INT
    trap 'handle_signal SIGTERM 143' TERM
    trap 'handle_exit' EXIT

    # 检查环境
    check_environment

    # 解析命令行参数
    parse_arguments "$@"

    # 自动生成镜像名称和标签
    generate_image_and_tag
    
    # 验证参数
    validate_arguments

    # 设置日志轮转
    setup_log_rotation

    # 显示构建信息
    log_info "════════════════════════════════════════"
    log_info "Jupyter Image Build Started"
    log_info "Image: ${OWNER}/${IMAGE_NAME}:${IMAGE_TAG}"
    log_info "Registry: ${REGISTRY}"
    log_info "Owner: ${OWNER}"
    if [[ ${#BUILD_ARGS[@]} -gt 0 ]]; then
        log_info "Build args: ${BUILD_ARGS[*]}"
    fi
    log_info "Log directory: $LOG_DIR"
    log_info "Log file: $LOG_FILE"
    log_info "PID: $$"
    log_info "════════════════════════════════════════"
    
    # 构建镜像
    if ! build_image; then
        exit $EXIT_CODE
    fi
    
    echo
    log_success "Build finished successfully!"

    # 验证镜像
    if ! verify_image; then
        exit $EXIT_CODE
    fi

    # 推送镜像（如果启用）
    if ! push_image; then
        exit $EXIT_CODE
    fi
    
    # 清理旧镜像（如果启用）
    if [[ "$CLEANUP" == true ]]; then
        cleanup_old_images
    fi

    # 显示构建摘要
    show_build_summary
    
    echo
    log_success "All done. You can now restart JupyterHub."
    
    if [[ -n "$LOG_FILE" ]]; then
        echo
        echo -e "${COLOR_BOLD}📝 Build log saved to:${COLOR_RESET} $LOG_FILE"
    fi
    
    # 正常退出
    EXIT_CODE=0
}

# ===== 执行 =====
main "$@"