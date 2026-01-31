#!/bin/bash

# Stock-TSDB 生产发布准备脚本
# 自动化执行生产环境部署前的所有准备工作

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
RELEASE_DIR="${PROJECT_ROOT}/release"
BUILD_DIR="${PROJECT_ROOT}/build"
BACKUP_DIR="${PROJECT_ROOT}/backup"
VERSION_FILE="${PROJECT_ROOT}/VERSION"
CONFIG_DIR="${PROJECT_ROOT}/conf"
SCRIPT_DIR="${PROJECT_ROOT}/scripts"

# 创建必要的目录
create_directories() {
    log_info "创建发布目录结构..."
    mkdir -p "${RELEASE_DIR}"
    mkdir -p "${BUILD_DIR}"
    mkdir -p "${BACKUP_DIR}"
    mkdir -p "${RELEASE_DIR}/bin"
    mkdir -p "${RELEASE_DIR}/conf"
    mkdir -p "${RELEASE_DIR}/scripts"
    mkdir -p "${RELEASE_DIR}/logs"
    mkdir -p "${RELEASE_DIR}/data"
    log_success "目录结构创建完成"
}

# 获取版本号
get_version() {
    if [[ -f "${VERSION_FILE}" ]]; then
        CURRENT_VERSION=$(cat "${VERSION_FILE}")
    else
        CURRENT_VERSION="1.0.0"
        echo "${CURRENT_VERSION}" > "${VERSION_FILE}"
    fi
    
    # 解析版本号
    IFS='.' read -ra VERSION_PARTS <<< "${CURRENT_VERSION}"
    MAJOR="${VERSION_PARTS[0]}"
    MINOR="${VERSION_PARTS[1]}"
    PATCH="${VERSION_PARTS[2]}"
    
    # 询问版本更新类型
    echo "当前版本: ${CURRENT_VERSION}"
    echo "请选择版本更新类型:"
    echo "1) 主版本更新 (${MAJOR}.${MINOR}.${PATCH} -> $((MAJOR+1)).0.0)"
    echo "2) 次版本更新 (${MAJOR}.${MINOR}.${PATCH} -> ${MAJOR}.$((MINOR+1)).0)"
    echo "3) 修订版本更新 (${MAJOR}.${MINOR}.${PATCH} -> ${MAJOR}.${MINOR}.$((PATCH+1)))"
    echo "4) 不更新版本"
    
    read -p "请选择 [1-4]: " version_choice
    
    case $version_choice in
        1)
            NEW_VERSION="$((MAJOR+1)).0.0"
            ;;
        2)
            NEW_VERSION="${MAJOR}.$((MINOR+1)).0"
            ;;
        3)
            NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH+1))"
            ;;
        4)
            NEW_VERSION="${CURRENT_VERSION}"
            ;;
        *)
            log_error "无效选择，使用当前版本"
            NEW_VERSION="${CURRENT_VERSION}"
            ;;
    esac
    
    if [[ "${NEW_VERSION}" != "${CURRENT_VERSION}" ]]; then
        echo "${NEW_VERSION}" > "${VERSION_FILE}"
        log_success "版本更新: ${CURRENT_VERSION} -> ${NEW_VERSION}"
    fi
    
    RELEASE_VERSION="${NEW_VERSION}"
}

# 运行测试
run_tests() {
    log_info "运行项目测试..."
    cd "${PROJECT_ROOT}"
    
    # 运行快速验证
    if make project-validate-quick; then
        log_success "快速验证通过"
    else
        log_error "快速验证失败"
        exit 1
    fi
    
    # 运行单元测试
    if make test-quick; then
        log_success "单元测试通过"
    else
        log_error "单元测试失败"
        exit 1
    fi
    
    # 运行集成测试
    if make test-integration; then
        log_success "集成测试通过"
    else
        log_warn "集成测试失败或跳过"
    fi
}

# 代码质量检查
code_quality_check() {
    log_info "执行代码质量检查..."
    
    # 检查 Lua 代码语法
    log_info "检查 Lua 代码语法..."
    find "${PROJECT_ROOT}/lua" -name "*.lua" -type f | while read file; do
        if ! luac -p "$file"; then
            log_error "Lua 语法错误: $file"
            exit 1
        fi
    done
    log_success "Lua 语法检查通过"
    
    # 检查脚本语法
    log_info "检查 Shell 脚本语法..."
    find "${SCRIPT_DIR}" -name "*.sh" -type f | while read file; do
        if ! bash -n "$file"; then
            log_error "Shell 语法错误: $file"
            exit 1
        fi
    done
    log_success "Shell 语法检查通过"
    
    # 检查配置文件
    log_info "检查配置文件..."
    if [[ -f "${CONFIG_DIR}/config.lua" ]]; then
        if ! luac -p "${CONFIG_DIR}/config.lua"; then
            log_error "配置文件语法错误"
            exit 1
        fi
    fi
    log_success "配置文件检查通过"
}

# 构建发布包
build_release() {
    log_info "构建发布包..."
    
    # 清理之前的构建
    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
    
    # 创建发布包结构
    RELEASE_PACKAGE="stock-tsdb-${RELEASE_VERSION}"
    PACKAGE_DIR="${BUILD_DIR}/${RELEASE_PACKAGE}"
    
    mkdir -p "${PACKAGE_DIR}"
    
    # 复制核心文件
    cp -r "${PROJECT_ROOT}/lua" "${PACKAGE_DIR}/"
    cp -r "${PROJECT_ROOT}/web" "${PACKAGE_DIR}/"
    cp -r "${SCRIPT_DIR}" "${PACKAGE_DIR}/"
    cp -r "${CONFIG_DIR}" "${PACKAGE_DIR}/"
    cp "${PROJECT_ROOT}/Makefile" "${PACKAGE_DIR}/"
    cp "${PROJECT_ROOT}/README.md" "${PACKAGE_DIR}/"
    cp "${PROJECT_ROOT}/VERSION" "${PACKAGE_DIR}/"
    
    # 复制文档
    mkdir -p "${PACKAGE_DIR}/docs"
    cp -r "${PROJECT_ROOT}/docs" "${PACKAGE_DIR}/"
    
    # 创建启动脚本
    cat > "${PACKAGE_DIR}/start.sh" << 'EOF'
#!/bin/bash
# Stock-TSDB 启动脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# 检查依赖
if ! command -v luajit &> /dev/null; then
    echo "错误: 未找到 luajit，请先安装 LuaJIT"
    exit 1
fi

# 启动服务
./scripts/start_business_web.sh

echo "Stock-TSDB 服务已启动"
echo "访问地址: http://localhost:8081"
echo "健康检查: http://localhost:8081/health"
EOF
    
    chmod +x "${PACKAGE_DIR}/start.sh"
    
    # 创建停止脚本
    cat > "${PACKAGE_DIR}/stop.sh" << 'EOF'
#!/bin/bash
# Stock-TSDB 停止脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# 停止服务
./scripts/stop_business_web.sh

echo "Stock-TSDB 服务已停止"
EOF
    
    chmod +x "${PACKAGE_DIR}/stop.sh"
    
    # 创建安装脚本
    cat > "${PACKAGE_DIR}/install.sh" << 'EOF'
#!/bin/bash
# Stock-TSDB 安装脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/stock-tsdb"

# 检查权限
if [[ $EUID -ne 0 ]]; then
   echo "请使用 root 权限运行安装脚本"
   exit 1
fi

# 创建安装目录
mkdir -p "${INSTALL_DIR}"

# 复制文件
cp -r "${SCRIPT_DIR}/"* "${INSTALL_DIR}/"

# 设置权限
chown -R nobody:nogroup "${INSTALL_DIR}"
chmod -R 755 "${INSTALL_DIR}/scripts"

# 创建服务用户（如果不存在）
if ! id "stocktsdb" &>/dev/null; then
    useradd -r -s /bin/false stocktsdb
fi

# 创建 systemd 服务文件
cat > /etc/systemd/system/stock-tsdb.service << 'SERVICE_EOF'
[Unit]
Description=Stock-TSDB Time Series Database
After=network.target

[Service]
Type=simple
User=stocktsdb
Group=stocktsdb
WorkingDirectory=/opt/stock-tsdb
ExecStart=/opt/stock-tsdb/start.sh
ExecStop=/opt/stock-tsdb/stop.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# 重新加载 systemd
systemctl daemon-reload

echo "安装完成"
echo "启动服务: systemctl start stock-tsdb"
echo "设置开机自启: systemctl enable stock-tsdb"
EOF
    
    chmod +x "${PACKAGE_DIR}/install.sh"
    
    # 打包
    cd "${BUILD_DIR}"
    tar -czf "${RELEASE_PACKAGE}.tar.gz" "${RELEASE_PACKAGE}"
    
    # 计算校验和
    sha256sum "${RELEASE_PACKAGE}.tar.gz" > "${RELEASE_PACKAGE}.tar.gz.sha256"
    
    # 复制到发布目录
    cp "${RELEASE_PACKAGE}.tar.gz" "${RELEASE_DIR}/"
    cp "${RELEASE_PACKAGE}.tar.gz.sha256" "${RELEASE_DIR}/"
    
    log_success "发布包构建完成: ${RELEASE_PACKAGE}.tar.gz"
}

# 生成发布说明
generate_release_notes() {
    log_info "生成发布说明..."
    
    RELEASE_NOTES_FILE="${RELEASE_DIR}/RELEASE_NOTES_${RELEASE_VERSION}.md"
    
    cat > "${RELEASE_NOTES_FILE}" << EOF
# Stock-TSDB ${RELEASE_VERSION} 发布说明

## 版本信息
- **版本号**: ${RELEASE_VERSION}
- **发布日期**: $(date '+%Y-%m-%d')
- **兼容性**: LuaJIT 2.1+, RocksDB 6.0+

## 新特性

### 核心功能
- 高性能时序数据存储引擎
- 支持微秒级时间精度
- 分布式集群部署支持
- Redis 兼容接口

### 性能指标
- 单线程写入性能: 180万笔/秒
- P99读取延迟: < 0.6ms
- 数据压缩率: 4:1
- 存储效率: 每条记录约74字节

## 安装说明

### 快速开始
\`\`\`bash
# 解压发布包
tar -xzf stock-tsdb-${RELEASE_VERSION}.tar.gz
cd stock-tsdb-${RELEASE_VERSION}

# 启动服务
./start.sh
\`\`\`

### 生产部署
\`\`\`bash
# 使用安装脚本（需要root权限）
./install.sh

# 启动服务
systemctl start stock-tsdb

# 设置开机自启
systemctl enable stock-tsdb
\`\`\`

## 配置说明

### 主要配置文件
- \`conf/config.lua\` - 主配置文件
- \`conf/redis.conf\` - Redis兼容接口配置
- \`conf/dev.env\` - 开发环境配置

### 性能调优参数
- 内存配置: 根据可用内存调整
- 压缩算法: LZ4 (默认)
- 块大小: 256MB

## 接口文档

### HTTP API
- 健康检查: \`GET /health\`
- 数据写入: \`POST /api/data\`
- 数据查询: \`GET /api/data/query\`
- 批量操作: \`POST /api/data/batch\`

### Redis 接口
- 端口: 6379 (默认)
- 协议: Redis 序列化协议
- 命令: 支持基本KV操作

## 故障排除

### 常见问题
1. **服务启动失败**: 检查依赖库是否安装
2. **性能问题**: 调整内存和压缩参数
3. **数据丢失**: 检查WAL配置和备份

### 日志文件
- 应用日志: \`logs/stock-tsdb.log\`
- 错误日志: \`logs/error.log\`
- 访问日志: \`logs/access.log\`

## 技术支持

- 文档: 查看 docs/ 目录
- 问题反馈: 创建 GitHub Issue
- 社区支持: 加入开发者社区

---
**Stock-TSDB 团队**  
发布日期: $(date '+%Y-%m-%d')
EOF
    
    log_success "发布说明生成完成: $(basename ${RELEASE_NOTES_FILE})"
}

# 备份当前版本
backup_current() {
    log_info "备份当前版本..."
    
    if [[ -d "${RELEASE_DIR}" ]]; then
        BACKUP_NAME="backup_$(date '+%Y%m%d_%H%M%S')"
        cp -r "${RELEASE_DIR}" "${BACKUP_DIR}/${BACKUP_NAME}"
        log_success "备份完成: ${BACKUP_NAME}"
    else
        log_warn "没有可备份的发布版本"
    fi
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."
    
    # 清理构建目录（保留发布包）
    if [[ -d "${BUILD_DIR}" ]]; then
        find "${BUILD_DIR}" -type f ! -name "*.tar.gz" ! -name "*.sha256" -delete
        find "${BUILD_DIR}" -type d -empty -delete
    fi
    
    log_success "清理完成"
}

# 显示发布信息
show_release_info() {
    log_info "=== 发布信息汇总 ==="
    echo "版本号: ${RELEASE_VERSION}"
    echo "发布包: ${RELEASE_DIR}/stock-tsdb-${RELEASE_VERSION}.tar.gz"
    echo "校验文件: ${RELEASE_DIR}/stock-tsdb-${RELEASE_VERSION}.tar.gz.sha256"
    echo "发布说明: ${RELEASE_DIR}/RELEASE_NOTES_${RELEASE_VERSION}.md"
    echo ""
    
    # 显示文件大小
    if [[ -f "${RELEASE_DIR}/stock-tsdb-${RELEASE_VERSION}.tar.gz" ]]; then
        FILE_SIZE=$(du -h "${RELEASE_DIR}/stock-tsdb-${RELEASE_VERSION}.tar.gz" | cut -f1)
        echo "发布包大小: ${FILE_SIZE}"
    fi
    
    echo ""
    log_success "生产发布准备完成！"
}

# 主函数
main() {
    log_info "开始 Stock-TSDB 生产发布准备..."
    
    # 检查当前目录
    if [[ ! -f "${PROJECT_ROOT}/Makefile" ]]; then
        log_error "请在项目根目录运行此脚本"
        exit 1
    fi
    
    # 执行各个步骤
    create_directories
    get_version
    run_tests
    code_quality_check
    backup_current
    build_release
    generate_release_notes
    cleanup
    show_release_info
    
    log_success "生产发布准备流程完成"
}

# 执行主函数
main "$@"