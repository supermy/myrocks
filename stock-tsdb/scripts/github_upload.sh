#!/bin/bash

# Stock-TSDB GitHub 上传脚本
# 自动化执行代码上传到 GitHub 仓库的所有步骤

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 配置变量
PROJECT_ROOT="/Users/moyong/project/ai/myrocks/stock-tsdb"
GITHUB_USER="your_github_username"  # 需要修改为实际的GitHub用户名
GITHUB_REPO="stock-tsdb"  # GitHub仓库名
GITHUB_TOKEN=""  # GitHub个人访问令牌（从环境变量获取）

# 检查 Git 配置
check_git_config() {
    log_info "检查 Git 配置..."
    
    # 检查是否在 Git 仓库中
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "当前目录不是 Git 仓库"
        exit 1
    fi
    
    # 检查远程仓库配置
    if ! git remote get-url origin > /dev/null 2>&1; then
        log_warn "未配置远程仓库，将自动配置"
        configure_remote_repo
    fi
    
    # 检查用户配置
    if [[ -z "$(git config user.name)" || -z "$(git config user.email)" ]]; then
        log_warn "Git 用户信息未配置"
        configure_git_user
    fi
    
    log_success "Git 配置检查完成"
}

# 配置 Git 用户信息
configure_git_user() {
    log_info "配置 Git 用户信息..."
    
    read -p "请输入 Git 用户名: " git_username
    read -p "请输入 Git 邮箱: " git_email
    
    git config user.name "${git_username}"
    git config user.email "${git_email}"
    
    log_success "Git 用户信息配置完成"
}

# 配置远程仓库
configure_remote_repo() {
    log_info "配置远程仓库..."
    
    read -p "请输入 GitHub 用户名: " github_user
    read -p "请输入仓库名 [stock-tsdb]: " github_repo
    
    github_user=${github_user:-${GITHUB_USER}}
    github_repo=${github_repo:-${GITHUB_REPO}}
    
    # 设置远程仓库URL
    git remote add origin "https://github.com/${github_user}/${github_repo}.git"
    
    log_success "远程仓库配置完成: ${github_user}/${github_repo}"
}

# 获取 GitHub 访问令牌
get_github_token() {
    log_info "获取 GitHub 访问令牌..."
    
    # 首先尝试从环境变量获取
    if [[ -n "${GITHUB_TOKEN}" ]]; then
        log_success "从环境变量获取到 GitHub 令牌"
        return 0
    fi
    
    # 尝试从 Git 配置获取
    local token=$(git config --global github.token)
    if [[ -n "${token}" ]]; then
        GITHUB_TOKEN="${token}"
        log_success "从 Git 配置获取到 GitHub 令牌"
        return 0
    fi
    
    # 提示用户输入
    echo "请提供 GitHub 个人访问令牌 (Personal Access Token)"
    echo "创建令牌: https://github.com/settings/tokens/new"
    echo "需要权限: repo (全部仓库权限)"
    echo ""
    
    read -s -p "请输入 GitHub 访问令牌: " token_input
    echo ""
    
    if [[ -z "${token_input}" ]]; then
        log_error "未提供 GitHub 访问令牌"
        exit 1
    fi
    
    GITHUB_TOKEN="${token_input}"
    
    # 询问是否保存到 Git 配置
    read -p "是否保存令牌到 Git 配置？(y/N): " save_token
    if [[ "${save_token}" =~ ^[Yy]$ ]]; then
        git config --global github.token "${GITHUB_TOKEN}"
        log_success "GitHub 令牌已保存到 Git 配置"
    fi
    
    log_success "GitHub 访问令牌获取完成"
}

# 检查代码状态
check_code_status() {
    log_info "检查代码状态..."
    
    # 检查是否有未提交的更改
    if ! git diff-index --quiet HEAD --; then
        log_warn "检测到未提交的更改"
        
        # 显示更改状态
        git status --short
        
        # 询问是否提交
        read -p "是否提交这些更改？(Y/n): " commit_changes
        if [[ "${commit_changes}" =~ ^[Yy]$ || -z "${commit_changes}" ]]; then
            commit_changes
        else
            log_warn "跳过提交，继续上传"
        fi
    else
        log_success "代码已是最新状态"
    fi
}

# 提交更改
commit_changes() {
    log_info "提交代码更改..."
    
    # 添加所有更改
    git add .
    
    # 获取提交信息
    if [[ -z "${COMMIT_MESSAGE}" ]]; then
        read -p "请输入提交信息: " commit_msg
        if [[ -z "${commit_msg}" ]]; then
            commit_msg="Update: $(date '+%Y-%m-%d %H:%M:%S')"
        fi
    else
        commit_msg="${COMMIT_MESSAGE}"
    fi
    
    # 执行提交
    git commit -m "${commit_msg}"
    
    log_success "代码提交完成: ${commit_msg}"
}

# 创建 GitHub 仓库（如果不存在）
create_github_repo() {
    log_info "检查 GitHub 仓库是否存在..."
    
    local repo_url="https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}"
    local response=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" "${repo_url}")
    
    # 检查仓库是否存在
    if echo "${response}" | grep -q '"message":"Not Found"'; then
        log_warn "GitHub 仓库不存在，将创建新仓库"
        
        # 创建仓库
        local create_data=$(cat << EOF
{
    "name": "${GITHUB_REPO}",
    "description": "High-performance time series database for stock market data built with LuaJIT and RocksDB",
    "homepage": "https://github.com/${GITHUB_USER}/${GITHUB_REPO}",
    "private": false,
    "has_issues": true,
    "has_projects": true,
    "has_wiki": true,
    "auto_init": false
}
EOF
        )
        
        local create_response=$(curl -s -X POST \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            -d "${create_data}" \
            "https://api.github.com/user/repos")
        
        if echo "${create_response}" | grep -q '"id"'; then
            log_success "GitHub 仓库创建成功: ${GITHUB_USER}/${GITHUB_REPO}"
        else
            log_error "GitHub 仓库创建失败"
            echo "响应: ${create_response}"
            exit 1
        fi
    else
        log_success "GitHub 仓库已存在"
    fi
}

# 推送代码到 GitHub
push_to_github() {
    log_info "推送代码到 GitHub..."
    
    # 获取当前分支
    local current_branch=$(git branch --show-current)
    
    # 设置上游分支
    git push --set-upstream origin "${current_branch}"
    
    if [[ $? -eq 0 ]]; then
        log_success "代码推送成功"
    else
        log_error "代码推送失败"
        
        # 尝试强制推送（需要确认）
        read -p "是否尝试强制推送？(y/N): " force_push
        if [[ "${force_push}" =~ ^[Yy]$ ]]; then
            git push --force origin "${current_branch}"
            if [[ $? -eq 0 ]]; then
                log_success "强制推送成功"
            else
                log_error "强制推送失败"
                exit 1
            fi
        else
            exit 1
        fi
    fi
}

# 创建标签和发布
create_release() {
    log_info "创建发布版本..."
    
    # 获取版本号
    local version_file="${PROJECT_ROOT}/VERSION"
    if [[ -f "${version_file}" ]]; then
        local version=$(cat "${version_file}")
    else
        local version="1.0.0"
    fi
    
    # 检查是否已存在该标签
    if git rev-parse "v${version}" > /dev/null 2>&1; then
        log_warn "标签 v${version} 已存在"
        read -p "是否删除并重新创建？(y/N): " recreate_tag
        if [[ "${recreate_tag}" =~ ^[Yy]$ ]]; then
            git tag -d "v${version}"
            git push --delete origin "v${version}"
        else
            return 0
        fi
    fi
    
    # 创建标签
    git tag -a "v${version}" -m "Release version ${version}"
    git push origin "v${version}"
    
    log_success "标签创建成功: v${version}"
    
    # 创建 GitHub Release
    create_github_release "${version}"
}

# 创建 GitHub Release
create_github_release() {
    local version="$1"
    
    log_info "创建 GitHub Release v${version}..."
    
    local release_data=$(cat << EOF
{
    "tag_name": "v${version}",
    "target_commitish": "main",
    "name": "Stock-TSDB v${version}",
    "body": "## Stock-TSDB v${version}\\n\\nHigh-performance time series database for stock market data.\\n\\n### Features\\n- Microsecond precision time series storage\\n- Built with LuaJIT and RocksDB\\n- Redis-compatible interface\\n- Distributed cluster support\\n\\n### Performance\\n- Write performance: 1.8M ops/sec per thread\\n- Read latency P99: < 0.6ms\\n- Compression ratio: 4:1\\n- Storage efficiency: ~74 bytes per record",
    "draft": false,
    "prerelease": false
}
EOF
    )
    
    local release_url="https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/releases"
    local response=$(curl -s -X POST \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "${release_data}" \
        "${release_url}")
    
    if echo "${response}" | grep -q '"id"'; then
        local release_id=$(echo "${response}" | grep -o '"id":[0-9]*' | cut -d: -f2)
        log_success "GitHub Release 创建成功 (ID: ${release_id})"
        
        # 上传发布包（如果存在）
        upload_release_assets "${release_id}" "${version}"
    else
        log_error "GitHub Release 创建失败"
        echo "响应: ${response}"
    fi
}

# 上传发布包资产
upload_release_assets() {
    local release_id="$1"
    local version="$2"
    
    local release_dir="${PROJECT_ROOT}/release"
    local package_file="${release_dir}/stock-tsdb-${version}.tar.gz"
    
    if [[ -f "${package_file}" ]]; then
        log_info "上传发布包资产..."
        
        local upload_url="https://uploads.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/releases/${release_id}/assets"
        
        # 上传压缩包
        curl -s -X POST \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Content-Type: application/gzip" \
            --data-binary "@${package_file}" \
            "${upload_url}?name=stock-tsdb-${version}.tar.gz"
        
        # 上传校验文件
        local checksum_file="${package_file}.sha256"
        if [[ -f "${checksum_file}" ]]; then
            curl -s -X POST \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Content-Type: text/plain" \
                --data-binary "@${checksum_file}" \
                "${upload_url}?name=stock-tsdb-${version}.tar.gz.sha256"
        fi
        
        log_success "发布包资产上传完成"
    else
        log_warn "未找到发布包文件，跳过资产上传"
    fi
}

# 设置仓库信息
setup_repository_info() {
    log_info "设置仓库信息..."
    
    # 创建 README.md（如果不存在）
    if [[ ! -f "README.md" ]]; then
        cat > README.md << 'EOF'
# Stock-TSDB

High-performance time series database for stock market data, built with LuaJIT and RocksDB.

## Features

- **Microsecond Precision**: Support for microsecond-level time series data
- **High Performance**: 1.8M operations per second per thread
- **Low Latency**: P99 read latency < 0.6ms
- **Efficient Storage**: 4:1 compression ratio, ~74 bytes per record
- **Redis Compatibility**: Redis-compatible interface
- **Distributed Support**: Built-in cluster deployment support

## Quick Start

```bash
# Clone the repository
git clone https://github.com/your-username/stock-tsdb.git
cd stock-tsdb

# Start the service
make dev-start

# Test the service
curl http://localhost:8081/health
```

## Documentation

- [Design Documentation](docs/chinese/design/综合设计文档.md)
- [API Reference](docs/api.md)
- [Performance Benchmarks](docs/performance.md)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
EOF
        log_success "README.md 创建完成"
    fi
    
    # 创建 .gitignore（如果不存在）
    if [[ ! -f ".gitignore" ]]; then
        cat > .gitignore << 'EOF'
# Build artifacts
build/
release/
backup/

# Runtime data
data/
logs/
*.log

# Dependencies
luarocks/
*.so
*.dylib
*.dll

# IDE files
.vscode/
.idea/
*.swp
*.swo

# OS files
.DS_Store
Thumbs.db

# Temporary files
*.tmp
*.temp
EOF
        log_success ".gitignore 创建完成"
    fi
    
    # 创建 LICENSE 文件（如果不存在）
    if [[ ! -f "LICENSE" ]]; then
        cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2024 Stock-TSDB Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
        log_success "LICENSE 文件创建完成"
    fi
}

# 显示上传结果
show_upload_result() {
    log_info "=== GitHub 上传结果 ==="
    
    local repo_url="https://github.com/${GITHUB_USER}/${GITHUB_REPO}"
    echo "仓库地址: ${repo_url}"
    echo ""
    
    # 获取最新提交信息
    local latest_commit=$(git log -1 --oneline)
    echo "最新提交: ${latest_commit}"
    
    # 获取当前分支
    local current_branch=$(git branch --show-current)
    echo "当前分支: ${current_branch}"
    
    # 获取标签信息
    local latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "无")
    echo "最新标签: ${latest_tag}"
    
    echo ""
    log_success "GitHub 上传完成！"
    echo "访问仓库: ${repo_url}"
}

# 主函数
main() {
    log_info "开始 Stock-TSDB GitHub 上传流程..."
    
    # 检查当前目录
    cd "${PROJECT_ROOT}"
    
    if [[ ! -f "Makefile" ]]; then
        log_error "请在项目根目录运行此脚本"
        exit 1
    fi
    
    # 执行各个步骤
    check_git_config
    get_github_token
    setup_repository_info
    check_code_status
    create_github_repo
    push_to_github
    create_release
    show_upload_result
    
    log_success "GitHub 上传流程完成"
}

# 显示帮助信息
show_help() {
    echo "Stock-TSDB GitHub 上传脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -m, --message  指定提交信息"
    echo "  -u, --user     指定 GitHub 用户名"
    echo "  -r, --repo     指定仓库名"
    echo ""
    echo "示例:"
    echo "  $0                          # 交互式上传"
    echo "  $0 -m '修复bug'             # 指定提交信息"
    echo "  $0 -u myusername -r myrepo   # 指定用户名和仓库名"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -m|--message)
            COMMIT_MESSAGE="$2"
            shift 2
            ;;
        -u|--user)
            GITHUB_USER="$2"
            shift 2
            ;;
        -r|--repo)
            GITHUB_REPO="$2"
            shift 2
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 执行主函数
main "$@"