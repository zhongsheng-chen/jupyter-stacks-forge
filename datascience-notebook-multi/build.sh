#!/usr/bin/env bash
set -euo pipefail

# ========================================
# build.sh - Jupyter base image builder for data science multi-env
#
# Usage:
#   ./build.sh [OPTIONS] [--build-arg KEY=VALUE ...]
#
# Options:
#   --kernels KERNELS     Which Python kernels to build:
#                           all/multi - Build all kernels (3.7, 3.8, 3.9, 3.10, 3.11, 3.12)
#                           py37      - Build Python 3.7 kernel
#                           py38      - Build Python 3.8 kernel
#                           py39      - Build Python 3.9 kernel
#                           py310     - Build Python 3.10 kernel
#                           py311     - Build Python 3.11 kernel
#                           py312     - Build Python 3.12 kernel
#                           (default: all)
#   --image NAME          Docker image name (default: zhongsheng/base-notebook)
#   --tag TAG             Docker image tag (default: auto-generated from --kernels value)
#   --no-cache            Disable Docker build cache
#   --log-dir DIR         Directory to store log files (default: logs/)
#   --verbose             Enable verbose output
#   --cleanup             Clean up old images after build
#   --push                Push image to registry after build
#   --registry REG        Docker registry to push to (if not specified, uses Docker Hub default)
#   --build-arg KV        Pass build arguments to Docker (can be used multiple times)
#                         Examples:
#                           --build-arg PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
#                           --build-arg INSTALL_ORACLE=false
#                           --build-arg EXTRA_APT_PKGS="htop vim"
#   -h, --help            Show this help message
#
# Examples:
#   ./build.sh                                                                   # default: all kernels
#   ./build.sh --kernels py310                                                   # build Python 3.10 kernel only
#   ./build.sh --kernels all --no-cache                                          # all kernels with no cache
#   ./build.sh --kernels py312 --image your/base-notebook --tag tag              # custom image and tag
#   ./build.sh --kernels py37 --push                                             # build and push to Docker Hub
#   ./build.sh --kernels all --push --registry myregistry.com:5000               # build and push to private registry
#   ./build.sh --kernels py39 --cleanup                                          # build and clean up old images
#   ./build.sh --kernels py310 --log-dir ./logs --verbose                        # save logs with debug output
#   ./build.sh --verbose                                                         # show debug output
#   ./build.sh --build-arg BUILD_TYPE=development                                # development build
#   ./build.sh --build-arg INSTALL_ORACLE=false                                  # build without Oracle
#   ./build.sh --build-arg EXTRA_APT_PKGS="htop vim"                             # add extra system packages
#   ./build.sh --build-arg PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/ # use Aliyun PyPI mirror
#   ./build.sh --build-arg PYTHON_VERSION=3.10
#   ./build.sh --build-arg BASE_IMAGE=jupyter/base-notebook
#   ./build.sh --build-arg BASE_TAG=python-3.10
#
# Notes:
#   - Base image (Python 3.10) serves only as bootstrap for Jupyter runtime
#   - Actual Python kernels (3.7, 3.8, 3.9, 3.10, 3.11, 3.12) are created via conda envs/environment-Python*.yml
#   - all/multi mode builds all kernels in a single image, making multiple kernels available in Jupyter
# ========================================

# ===== 全局配置 =====
readonly DEFAULT_IMAGE_NAME="base-notebook"
readonly DEFAULT_TAG="python-3.10"
readonly DEFAULT_KERNELS="all"
readonly DEFAULT_LOG_DIR="logs/"
readonly DEFAULT_REGISTRY="docker.io"        # 默认 registry
readonly DEFAULT_OWNER="zhongsheng"          # 默认所有者
readonly SCRIPT_NAME="$(basename "$0")"
readonly TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
readonly MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB
readonly DOCKERFILE="Dockerfile"

# Python 版本映射
declare -A PYTHON_VERSION_MAP=(
    ["py37"]="3.7"
    ["py38"]="3.8"
    ["py39"]="3.9"
    ["py310"]="3.10"
    ["py311"]="3.11"
    ["py312"]="3.12"
)

# ===== 颜色配置 =====
if [[ -t 1 ]] && [[ "$TERM" != "dumb" ]]; then
    readonly COLOR_RESET="\033[0m"
    readonly COLOR_RED="\033[0;31m"
    readonly COLOR_GREEN="\033[0;32m"
    readonly COLOR_YELLOW="\033[0;33m"
    readonly COLOR_BLUE="\033[0;34m"
    readonly COLOR_MAGENTA="\033[0;35m"
    readonly COLOR_CYAN="\033[0;36m"
    readonly COLOR_BOLD="\033[1m"
    readonly COLOR_DIM="\033[2m"
else
    readonly COLOR_RESET=""
    readonly COLOR_RED=""
    readonly COLOR_GREEN=""
    readonly COLOR_YELLOW=""
    readonly COLOR_BLUE=""
    readonly COLOR_MAGENTA=""
    readonly COLOR_CYAN=""
    readonly COLOR_BOLD=""
    readonly COLOR_DIM=""
fi

# ===== 全局变量 =====
KERNELS="$DEFAULT_KERNELS"
PYTHON_VERSION=""
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
    echo -e ""
    echo -e "${COLOR_BOLD}Options:${COLOR_RESET}"
    echo -e "  --kernels KERNELS     Which Python kernels to build:"
    echo -e "                           all/multi - Build all kernels (3.7, 3.8, 3.9, 3.10, 3.11, 3.12)"
    echo -e "                           py37      - Build Python 3.7 kernel"
    echo -e "                           py38      - Build Python 3.8 kernel"
    echo -e "                           py39      - Build Python 3.9 kernel"
    echo -e "                           py310     - Build Python 3.10 kernel"
    echo -e "                           py311     - Build Python 3.11 kernel"
    echo -e "                           py312     - Build Python 3.12 kernel"
    echo -e "                           (default: ${COLOR_CYAN}all${COLOR_RESET})"
    echo -e "  --image NAME          Docker image name (default: ${COLOR_CYAN}${DEFAULT_IMAGE_NAME}${COLOR_RESET})"
    echo -e "                        Can be specified as:"
    echo -e "                          - simple name: base-notebook (uses --owner)"
    echo -e "                          - full name:   yourname/base-notebook (ignores --owner)"
    echo -e "  --owner OWNER         Docker Hub owner/username (default: ${COLOR_CYAN}${DEFAULT_OWNER}${COLOR_RESET})"
    echo -e "                        Used with --image when image name doesn't include owner"
    echo -e "  --tag TAG             Docker image tag (default: auto-generated from --kernels value)"
    echo -e "  --no-cache            Disable Docker build cache"
    echo -e "  --log-dir DIR         Directory to store log files (default: ${COLOR_CYAN}${DEFAULT_LOG_DIR}${COLOR_RESET})"
    echo -e "  --verbose             Enable verbose output"
    echo -e "  --cleanup             Clean up old images after build"
    echo -e "  --push                Push image to registry after build"
    echo -e "  --registry REG        Docker registry to use (default: ${COLOR_CYAN}${DEFAULT_REGISTRY}${COLOR_RESET})"
    echo -e "                        Examples:"
    echo -e "                          - docker.io (Docker Hub)"
    echo -e "                          - myregistry.com:5000 (private registry)"
    echo -e "                          - myregistry.azurecr.io (Azure Container Registry)"
    echo -e "                          - 192.168.1.100:5000 (local registry)"
    echo -e "  --build-arg KV        Pass build arguments to Docker (can be used multiple times)"
    echo -e "                        Examples:"
    echo -e "                          --build-arg PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/"
    echo -e "                          --build-arg INSTALL_ORACLE=false"
    echo -e "                          --build-arg EXTRA_APT_PKGS=\"htop vim\""
    echo -e "  -h, --help            Show this help message"
    echo -e ""
    echo -e "${COLOR_BOLD}Examples:${COLOR_RESET}"
    echo -e "  $0                                                                                       # default: ${DEFAULT_REGISTRY}/${DEFAULT_OWNER}/${DEFAULT_IMAGE_NAME}:${DEFAULT_TAG}"
    echo -e "  $0 --owner yourname                                                                      # ${DEFAULT_REGISTRY}/yourname/${DEFAULT_IMAGE_NAME}:${DEFAULT_TAG}"
    echo -e "  $0 --image custom-notebook                                                               # ${DEFAULT_REGISTRY}/${DEFAULT_OWNER}/custom-notebook:${DEFAULT_TAG}"
    echo -e "  $0 --owner yourname --image custom-notebook                                              # ${DEFAULT_REGISTRY}/yourname/custom-notebook:${DEFAULT_TAG}"
    echo -e "  $0 --image yourname/custom-notebook                                                      # ${DEFAULT_REGISTRY}/yourname/custom-notebook:${DEFAULT_TAG} (--owner ignored)"
    echo -e "  $0 --kernels py310                                                                       # build Python 3.10 kernel only"
    echo -e "  $0 --kernels all --no-cache                                                              # all kernels with no cache"
    echo -e "  $0 --kernels py312 --image your/base-notebook --tag tag                                  # custom image and tag"
    echo -e "  $0 --kernels py37 --push                                                                 # build and push to Docker Hub"
    echo -e "  $0 --kernels all --push --registry myregistry.com:5000                                   # build and push to private registry"
    echo -e "  $0 --registry myregistry.com:5000 --owner yourname --image custom-notebook               # myregistry.com:5000/yourname/custom-notebook:${DEFAULT_TAG}"
    echo -e "  $0 --kernels py39 --cleanup                                                              # build and clean up"
    echo -e "  $0 --kernels py310 --log-dir ./logs --verbose                                            # save logs with debug"
    echo -e "  $0 --verbose                                                                             # show debug output"
    echo -e "  $0 --build-arg BUILD_TYPE=development                                                    # development build"
    echo -e "  $0 --build-arg INSTALL_ORACLE=false                                                      # build without Oracle"
    echo -e "  $0 --build-arg EXTRA_APT_PKGS=\"htop vim\"                                                 # add extra system packages"
    echo -e "  $0 --build-arg PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/                     # use Aliyun PyPI mirror"
    echo -e "  $0 --build-arg PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/                     # use Aliyun PyPI mirror"
    echo -e "  $0 --build-arg PYTHON_VERSION=3.10"
    echo -e "  $0 --build-arg BASE_IMAGE=jupyter/base-notebook"
    echo -e "  $0 --build-arg BASE_TAG=python-3.10"
    echo -e ""
    echo -e "${COLOR_BOLD}Notes:${COLOR_RESET}"
    echo -e "  • Base image (Python 3.10) serves only as bootstrap for Jupyter runtime"
    echo -e "  • Actual Python kernels (3.7, 3.8, 3.9, 3.10, 3.11, 3.12) are created via conda envs/environment-Python*.yml"
    echo -e "  • all/multi mode builds all kernels in a single image, making multiple kernels available in Jupyter"
    echo -e ""
    echo -e "${COLOR_BOLD}Result:${COLOR_RESET}"
    echo -e "  <REGISTRY>/<IMAGE_NAME>:<TAG>"

    trap - EXIT INT TERM
    exit 0
}

# ===== 检查环境 =====
check_environment() {
    log_debug "Checking environment..."
    
    # 检查 Docker 是否安装
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker first."
    fi
    
    # 检查 Docker 守护进程是否运行
    if ! docker info &> /dev/null 2>&1; then
        log_error "Docker daemon is not running or permission denied."
    fi
    
    # 检查 Dockerfile 是否存在
    if [[ ! -f "$DOCKERFILE" ]]; then
        log_error "$DOCKERFILE not found in current directory"
    fi
    
    # 检查必要的目录和文件
    if [[ ! -d "envs" ]]; then
        log_error "envs/ directory not found"
    fi
    
    # 检查是否有环境文件
    local env_count=$(ls envs/environment-Python*.yml 2>/dev/null | wc -l)
    if [[ $env_count -eq 0 ]]; then
        log_error "No environment-Python*.yml files found in envs/"
    fi
    
    # 检查 requirements 文件
    local required_files=(
        "requirements-core.txt"
        "requirements-ml.txt" 
        "requirements-db.txt"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file not found: $file"
        fi
    done
    
    # 检查 common 目录
    if [[ ! -d "../common" ]]; then
        log_warning "Common directory not found at ../common. Database clients and wheels may be missing."
    else
        # 检查 common 子目录（只警告，不中断构建）
        if [[ ! -d "../common/db_clients" ]]; then
            log_warning "db_clients directory not found in common, database clients may be missing"
        fi
        if [[ ! -d "../common/wheels" ]]; then
            log_warning "wheels directory not found in common, custom wheels may be missing"
        fi
    fi
    
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
        local wait_time=0
        while kill -0 "$BUILD_PID" 2>/dev/null && [[ $wait_time -lt 5 ]]; do
            sleep 1
            wait_time=$((wait_time + 1))
            echo -n "."
        done
        echo
        
        # 如果进程还在，强制终止
        if kill -0 "$BUILD_PID" 2>/dev/null; then
            log_warning "Build process did not respond to $signal, forcing kill..."
            kill -KILL "$BUILD_PID" 2>/dev/null || true
        fi
    fi
    
    # 清理临时目录
    log_info "Cleaning up temporary directories..."
    cleanup_build_context
    
    # 调用退出处理
    handle_exit
}

# ===== 参数解析 =====
parse_arguments() {
    # 初始化变量
    KERNELS="$DEFAULT_KERNELS"
    IMAGE_NAME="$DEFAULT_IMAGE_NAME"
    IMAGE_TAG=""
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
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --kernels)
                if [[ -n "${2:-}" ]]; then
                    KERNELS="$2"
                    log_debug "Kernels set to: $KERNELS"
                    shift 2
                else
                    log_error "--kernels requires a kernel specification"
                    EXIT_CODE=1
                    exit 1
                fi
                ;;
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
                    log_debug "Image tag set to: $IMAGE_TAG"
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
                    log_debug "Log directory set to: $LOG_DIR"
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
                    log_debug "Registry set to: $REGISTRY"
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
                log_error "Unexpected argument: $1"
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
    # 验证 kernels 参数
    if [[ "$KERNELS" == "all" || "$KERNELS" == "multi" ]]; then
        PYTHON_VERSION="multi"
        log_debug "Building all Python kernels"
        
        # 验证是否有环境文件（只检查，不输出日志）
        local count=$(ls envs/environment-Python*.yml 2>/dev/null | wc -l)
        if [[ "$count" -eq 0 ]]; then
            log_error "No environment-Python*.yml found in envs/"
            EXIT_CODE=1
            exit 1
        fi
        
    elif [[ "$KERNELS" =~ ^py(37|38|39|310|311|312)$ ]]; then
        # 格式: py37, py38, py39, py310, py311, py312
        local py_key="$KERNELS"
        if [[ -n "${PYTHON_VERSION_MAP[$py_key]:-}" ]]; then
            PYTHON_VERSION="${PYTHON_VERSION_MAP[$py_key]}"
            log_debug "Building kernel: $KERNELS (Python $PYTHON_VERSION)"
            
            local yml="envs/environment-Python${PYTHON_VERSION}.yml"
            if [[ ! -f "$yml" ]]; then
                log_error "Missing conda env file for Python $PYTHON_VERSION: $yml"
                EXIT_CODE=1
                exit 1
            fi
        else
            log_error "Invalid kernel format: $KERNELS"
            log_error "Supported kernels: all, multi, py37, py38, py39, py310, py311, py312"
            EXIT_CODE=1
            exit 1
        fi
    else
        log_error "Invalid kernels argument: $KERNELS"
        log_error "Supported kernels: all, multi, py37, py38, py39, py310, py311, py312"
        EXIT_CODE=1
        exit 1
    fi
    
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
            echo "Kernels: $KERNELS -> Python version: $PYTHON_VERSION"
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
    local base_image="jupyter/base-notebook"
    local base_tag="python-3.10"
    
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
    
    # 检查用户是否指定了自定义镜像名（与默认值不同）
    if [[ "$IMAGE_NAME" != "$DEFAULT_IMAGE_NAME" ]]; then
        user_specified_image=true
    fi
    
    # 检查用户是否指定了自定义标签（非空）
    if [[ -n "$IMAGE_TAG" ]]; then
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
    
    # 从 base_tag 中提取基础 Python 版本
    local base_python_version=""
    if [[ "$base_tag" =~ ^python-([0-9]+\.[0-9]+)$ ]]; then
        base_python_version="${BASH_REMATCH[1]}"
        log_debug "Extracted base Python version: $base_python_version"
    fi
    
    # 检查是否通过 --build-arg 指定了 BASE_IMAGE 和 BASE_TAG
    local base_image_specified=false
    local base_tag_specified=false
    
    # 从 BUILD_ARGS 中提取 PYTHON_VERSION
    local python_version=""
    
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
                PYTHON_VERSION=*)
                    python_version="${arg#PYTHON_VERSION=}"
                    log_debug "PYTHON_VERSION was specified via --build-arg: $python_version"
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
        # 从 base_tag 提取 Python 版本（如果可能）
        if [[ "$base_tag" =~ ^python-([0-9]+\.[0-9]+)$ ]]; then
            local extracted_version="${BASH_REMATCH[1]}"
            # 如果也有 PYTHON_VERSION，使用它
            if [[ -n "$python_version" ]]; then
                IMAGE_TAG="python-${python_version}"
            else
                IMAGE_TAG="$base_tag"
            fi
        else
            IMAGE_TAG="$base_tag"
        fi
        log_info "Auto-generated image tag: $IMAGE_TAG (from BASE_TAG=$base_tag)"
    fi
    
    # 确保 IMAGE_TAG 有值（如果没有通过任何方式设置）
    if [[ -z "$IMAGE_TAG" ]]; then
        # 优先级：PYTHON_VERSION build arg > KERNELS > DEFAULT_TAG
        if [[ -n "$python_version" ]]; then
            # 如果指定了 PYTHON_VERSION build arg，使用它
            if [[ "$python_version" == "multi" ]]; then
                IMAGE_TAG="multi"
            else
                # 生成格式：base-py3.10-kernel-py3.7
                if [[ -n "$base_python_version" ]]; then
                    IMAGE_TAG="base-py${base_python_version}-kernel-py${python_version}"
                else
                    IMAGE_TAG="python-${python_version}"
                fi
            fi
            log_debug "Using tag from PYTHON_VERSION: $IMAGE_TAG"
        elif [[ -n "$KERNELS" ]]; then
            # 从 --kernels 参数生成标签
            case "$KERNELS" in
                all|multi)
                    if [[ -n "$base_python_version" ]]; then
                        IMAGE_TAG="base-py${base_python_version}-kernel-multi"
                    else
                        IMAGE_TAG="multi"
                    fi
                    log_debug "Using tag from KERNELS (multi): $IMAGE_TAG"
                    ;;
                py37)
                    if [[ -n "$base_python_version" ]]; then
                        IMAGE_TAG="base-py${base_python_version}-kernel-py3.7"
                    else
                        IMAGE_TAG="python-3.7"
                    fi
                    log_debug "Using tag from KERNELS (py37): $IMAGE_TAG"
                    ;;
                py38)
                    if [[ -n "$base_python_version" ]]; then
                        IMAGE_TAG="base-py${base_python_version}-kernel-py3.8"
                    else
                        IMAGE_TAG="python-3.8"
                    fi
                    log_debug "Using tag from KERNELS (py38): $IMAGE_TAG"
                    ;;
                py39)
                    if [[ -n "$base_python_version" ]]; then
                        IMAGE_TAG="base-py${base_python_version}-kernel-py3.9"
                    else
                        IMAGE_TAG="python-3.9"
                    fi
                    log_debug "Using tag from KERNELS (py39): $IMAGE_TAG"
                    ;;
                py310)
                    if [[ -n "$base_python_version" ]]; then
                        IMAGE_TAG="base-py${base_python_version}-kernel-py3.10"
                    else
                        IMAGE_TAG="python-3.10"
                    fi
                    log_debug "Using tag from KERNELS (py310): $IMAGE_TAG"
                    ;;
                py311)
                    if [[ -n "$base_python_version" ]]; then
                        IMAGE_TAG="base-py${base_python_version}-kernel-py3.11"
                    else
                        IMAGE_TAG="python-3.11"
                    fi
                    log_debug "Using tag from KERNELS (py311): $IMAGE_TAG"
                    ;;
                py312)
                    if [[ -n "$base_python_version" ]]; then
                        IMAGE_TAG="base-py${base_python_version}-kernel-py3.12"
                    else
                        IMAGE_TAG="python-3.12"
                    fi
                    log_debug "Using tag from KERNELS (py312): $IMAGE_TAG"
                    ;;
                *)
                    # 如果无法识别，使用 kernels 值本身
                    if [[ -n "$base_python_version" ]]; then
                        IMAGE_TAG="base-py${base_python_version}-kernel-${KERNELS}"
                    else
                        IMAGE_TAG="$KERNELS"
                    fi
                    log_debug "Using tag from KERNELS (direct): $IMAGE_TAG"
                    ;;
            esac
        else
            # 最后使用默认值
            IMAGE_TAG="$DEFAULT_TAG"
            log_debug "Using default tag: $IMAGE_TAG"
        fi
    fi

    log_debug "generate_image_and_tag completed"
}

# ===== 准备构建上下文 =====
prepare_build_context() {
    log_debug "Preparing build context..."
    
    # 检查 common 目录是否存在
    if [[ ! -d "../common" ]]; then
        log_error "Common directory not found at ../common"
        exit 1
    fi
    
    # 检查 wheels 和 db_clients 子目录
    if [[ ! -d "../common/wheels" ]]; then
        log_warning "wheels directory not found in common"
    fi
    
    if [[ ! -d "../common/db_clients" ]]; then
        log_warning "db_clients directory not found in common"
    fi
    
    # 创建临时目录
    mkdir -p wheels db_clients
    
    # 复制 wheels 文件（跟随软链接）
    if [[ -d "../common/wheels" ]] && [[ -n "$(ls -A ../common/wheels 2>/dev/null)" ]]; then
        log_debug "Copying wheel files from ../common/wheels"
        cp -rvL ../common/wheels/* wheels/ 2>&1 | while read line; do log_debug "$line"; done
        log_debug "Copied $(ls wheels/ 2>/dev/null | wc -l) wheel files"
    fi
    
    # 复制 db_clients 文件（跟随软链接）
    if [[ -d "../common/db_clients" ]] && [[ -n "$(ls -A ../common/db_clients 2>/dev/null)" ]]; then
        log_debug "Copying db_client files from ../common/db_clients"
        cp -rvL ../common/db_clients/* db_clients/ 2>&1 | while read line; do log_debug "$line"; done
        log_debug "Copied $(ls db_clients/ 2>/dev/null | wc -l) db_client files"
    fi
}

# ===== 清理构建上下文 =====
cleanup_build_context() {
    local cleaned=false
    
    # 删除临时目录
    if [[ -d "wheels" ]]; then
        rm -rf wheels
        log_debug "Removed wheels directory"
        cleaned=true
    fi
    
    if [[ -d "db_clients" ]]; then
        rm -rf db_clients
        log_debug "Removed db_clients directory"
        cleaned=true
    fi
    
    if [[ "$cleaned" == true ]]; then
        log_info "Temporary directories cleaned up"
    fi
}

# ===== 构建镜像 =====
build_image() {
    prepare_build_context

    local full_image="${IMAGE_NAME}:${IMAGE_TAG}"
    local build_cmd="docker build"
    
    # 获取基础镜像信息
    local base_image
    base_image=$(get_base_image)
    
    # 在这里输出环境文件信息，确保在构建开始信息之后
    if [[ "$PYTHON_VERSION" == "multi" ]]; then
        local count=$(ls envs/environment-Python*.yml 2>/dev/null | wc -l)
        log_info "Found $count Python environment files (py37, py38, py39, py310, py311, py312)"
    else
        local yml="envs/environment-Python${PYTHON_VERSION}.yml"
        log_info "Using environment file: environment-Python${PYTHON_VERSION}.yml"
    fi
    
    log_info "Starting build process"
    log_info "Building image: $full_image"
    log_info "Base image (bootstrap): $base_image"
    if [[ "$PYTHON_VERSION" == "multi" ]]; then
        log_info "Target kernels: all (py37, py38, py39, py310, py311, py312)"
    else
        log_info "Target kernel: $KERNELS (Python $PYTHON_VERSION)"
    fi
    
    # 构建命令参数
    if [[ "$NO_CACHE" == true ]]; then
        build_cmd="$build_cmd --no-cache --pull"
        log_info "Build cache: disabled (will pull latest base image)"
    else
        build_cmd="$build_cmd --pull"
        log_info "Build cache: enabled (will pull latest base image)"
    fi
    
    # 添加基础镜像相关的 build args
    build_cmd="$build_cmd --build-arg PYTHON_VERSION=\"$PYTHON_VERSION\""
    build_cmd="$build_cmd --build-arg BASE_IMAGE=\"$(echo $base_image | cut -d: -f1)\""
    build_cmd="$build_cmd --build-arg BASE_TAG=\"$(echo $base_image | cut -d: -f2)\""
    
    # 添加用户自定义 build args
    if [[ ${#BUILD_ARGS[@]} -gt 0 ]]; then
        build_cmd="$build_cmd ${BUILD_ARGS[*]}"
        log_info "Custom build arguments: ${COLOR_CYAN}${BUILD_ARGS[*]}${COLOR_RESET}"
    fi
    
    build_cmd="$build_cmd -t $full_image -f $DOCKERFILE ."
    log_debug "Build command: $build_cmd"
    
    # 显示构建信息
    echo -e "\n${COLOR_BOLD}${COLOR_CYAN}════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}🚀 Building Jupyter image${COLOR_RESET}"
    echo -e "${COLOR_BOLD}${COLOR_CYAN}════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BOLD}Output image:${COLOR_RESET} $full_image"
    echo -e "${COLOR_BOLD}Base image (bootstrap):${COLOR_RESET} $base_image"
    if [[ "$PYTHON_VERSION" == "multi" ]]; then
        echo -e "${COLOR_BOLD}Target kernels:${COLOR_RESET} all (py37, py38, py39, py310, py311, py312)"
    else
        echo -e "${COLOR_BOLD}Target kernel:${COLOR_RESET} $KERNELS (Python $PYTHON_VERSION)"
    fi
    
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
    
    # 非 verbose 模式下显示简单提示
    if [[ "$VERBOSE" == false ]]; then
        echo -e "${COLOR_DIM}Build in progress... (use --verbose to see detailed output)${COLOR_RESET}"
    fi
    
    # 等待构建完成并获取退出码
    wait $BUILD_PID
    local build_exit_code=$?
    BUILD_PID=""  # 清除PID，表示构建已完成

    cleanup_build_context
    
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
    
    # 验证 Jupyter 可用性
    echo -e "\n${COLOR_BOLD}📓 Checking Jupyter...${COLOR_RESET}"
    if timeout 30s docker run --rm "$full_image" jupyter --version &>/dev/null; then
        log_success "Jupyter is available"
        echo -e "${COLOR_GREEN}✅ Jupyter OK${COLOR_RESET}"
    else
        log_error "Jupyter not found in image!"
        echo -e "${COLOR_RED}❌ Jupyter check failed${COLOR_RESET}"
        EXIT_CODE=1
        return 1
    fi
    
    # 列出可用的 kernels
    echo -e "\n${COLOR_BOLD}🧠 Available Jupyter kernels:${COLOR_RESET}"
    if timeout 30s docker run --rm "$full_image" jupyter kernelspec list 2>/dev/null; then
        log_success "Kernel listing successful"
    else
        log_warning "Could not list kernels"
    fi
    
    # 验证 Python 环境
    if [[ "$PYTHON_VERSION" == "multi" ]]; then
        echo -e "\n${COLOR_BOLD}🐍 Checking Python kernels...${COLOR_RESET}"
        # 检查每个 Python 版本
        for py_key in py37 py38 py39 py310 py311 py312; do
            local py_ver="${PYTHON_VERSION_MAP[$py_key]}"
            local env_name="python${py_ver//./}"  # 3.7 -> python37
            if timeout 10s docker run --rm "$full_image" bash -c "source /opt/conda/etc/profile.d/conda.sh && conda activate $env_name && python --version" &>/dev/null; then
                echo -e "${COLOR_GREEN}✅ $py_key (Python $py_ver) kernel available${COLOR_RESET}"
            else
                log_warning "$py_key (Python $py_ver) kernel may not be available"
            fi
        done
    else
        echo -e "\n${COLOR_BOLD}🐍 Checking $KERNELS kernel...${COLOR_RESET}"
        local env_name="python${PYTHON_VERSION//./}"  # 3.7 -> python37
        if timeout 10s docker run --rm "$full_image" bash -c "source /opt/conda/etc/profile.d/conda.sh && conda activate $env_name && python --version"; then
            log_success "$KERNELS (Python $PYTHON_VERSION) kernel is available"
        else
            log_error "$KERNELS (Python $PYTHON_VERSION) kernel not found!"
            EXIT_CODE=1
            return 1
        fi
    fi
    
    # 获取镜像大小
    echo -e "\n${COLOR_BOLD}📦 Image details:${COLOR_RESET}"
    local image_size
    image_size=$(docker image inspect "$full_image" --format '{{.Size}}')
    local size_mb=$((image_size / 1024 / 1024))
    echo -e "Size: $size_mb MB"
    log_info "Image size: $size_mb MB"
    
    return 0
}

# ===== 推送镜像 =====
push_image() {
    if [[ "$PUSH" != true ]]; then
        return 0
    fi
    
    local full_image="${IMAGE_NAME}:${IMAGE_TAG}"
    local push_image="$full_image"
    
    # 如果指定了 registry，则添加 registry 前缀
    if [[ -n "$REGISTRY" ]]; then
        push_image="${REGISTRY}/${full_image}"
    fi
    
    log_info "Pushing image to registry: $push_image"
    echo -e "\n${COLOR_BOLD}📤 Pushing image to registry...${COLOR_RESET}"
    
    # 如果 registry 与默认不同，需要先打标签
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
    local push_image="$full_image"
    
    if [[ -n "$REGISTRY" ]] && [[ "$PUSH" == true ]]; then
        push_image="${REGISTRY}/${full_image}"
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
    
    if [[ "$PYTHON_VERSION" == "multi" ]]; then
        echo -e "${COLOR_BOLD}Kernels:${COLOR_RESET} py37, py38, py39, py310, py311, py312 (Python 3.7-3.12)"
    else
        echo -e "${COLOR_BOLD}Kernel:${COLOR_RESET} $KERNELS (Python $PYTHON_VERSION)"
    fi
    
    if [[ "$PUSH" == true ]]; then
        if [[ -n "$REGISTRY" ]]; then
            echo -e "${COLOR_BOLD}Pushed to:${COLOR_RESET} ${push_image}"
        else
            echo -e "${COLOR_BOLD}Pushed to:${COLOR_RESET} Docker Hub (${full_image})"
        fi
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
    log_info "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
    log_info "Kernels: ${KERNELS} -> ${PYTHON_VERSION}"
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
    if [[ "$PYTHON_VERSION" == "multi" ]]; then
        log_success "All done. Jupyter now has kernels for py37, py38, py39, py310, py311, py312"
    else
        log_success "All done. Jupyter now has kernel for $KERNELS (Python $PYTHON_VERSION)"
    fi
    
    if [[ -n "$LOG_FILE" ]]; then
        echo
        echo -e "${COLOR_BOLD}📝 Build log saved to:${COLOR_RESET} $LOG_FILE"
    fi
    
    # 正常退出
    EXIT_CODE=0
}

# ===== 执行主函数 =====
main "$@"