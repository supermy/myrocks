# 股票行情数据TSDB系统 - 优化版 Makefile
# 基于 LuaJIT 的轻量级时间序列数据库

# =============================================================================
# 基础配置
# =============================================================================
PROJECT_NAME = stock-tsdb
VERSION = 1.0.0
LUAROCKS = luarocks
LUAJIT_BIN = luajit

# 目录配置
SRC_DIR = src
BIN_DIR = bin
CONF_DIR = conf
LUA_DIR = lua
LIB_DIR = lib
LOGS_DIR = logs
DATA_DIR = data
TEST_DIR = tests
EXAMPLES_DIR = examples
DOCS_DIR = docs
SCRIPTS_DIR = scripts
WEB_DIR = web

# 系统检测
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    PLATFORM = linux
    LUA_INCDIR = /usr/include/luajit-2.1
    LUA_LIBDIR = /usr/lib
    LUA_VERSION = 5.1
endif
ifeq ($(UNAME_S),Darwin)
    PLATFORM = macos
    LUA_INCDIR = /usr/local/include/luajit-2.1
    LUA_LIBDIR = /usr/local/lib
    LUA_VERSION = 5.2
endif

# 用户主目录
USER_HOME = $(HOME)
LUAROCKS_LOCAL_LIB = $(USER_HOME)/.luarocks/lib/lua/$(LUA_VERSION)

# 路径配置
LUA_PATH = ./$(LUA_DIR)/?.lua;./?.lua;./$(LUA_DIR)/?/init.lua;;
LUA_CPATH = ./$(LIB_DIR)/?.so;./?.so;$(LUAROCKS_LOCAL_LIB)/?.so;;

# =============================================================================
# 主要目标
# =============================================================================
.PHONY: all build install clean test help check-deps install-deps

all: check-deps build

# =============================================================================
# 依赖管理
# =============================================================================
check-deps:
	@echo "🔍 检查系统依赖..."
	@which $(LUAJIT_BIN) > /dev/null && echo "✅ LuaJIT 已安装" || (echo "❌ LuaJIT 未安装" && exit 1)
	@which $(LUAROCKS) > /dev/null && echo "✅ LuaRocks 已安装" || (echo "❌ LuaRocks 未安装" && exit 1)
	@echo "✅ 依赖检查完成"

install-deps: check-deps install-cjson install-dkjson install-luafilesystem
	@echo "✅ 所有依赖安装完成"

install-cjson:
	@echo "📦 安装cjson模块..."
	@if $(LUAROCKS) list | grep -q "lua-cjson"; then \
		echo "✅ cjson模块已安装"; \
	else \
		$(LUAROCKS) install --local lua-cjson && echo "✅ cjson模块安装成功" || (echo "❌ cjson模块安装失败" && exit 1); \
	fi

install-dkjson:
	@echo "📦 安装dkjson模块..."
	@if $(LUAROCKS) list | grep -q "dkjson"; then \
		echo "✅ dkjson模块已安装"; \
	else \
		$(LUAROCKS) install --local dkjson && echo "✅ dkjson模块安装成功" || (echo "❌ dkjson模块安装失败" && exit 1); \
	fi

install-luafilesystem:
	@echo "📦 安装luafilesystem模块..."
	@if $(LUAROCKS) list | grep -q "luafilesystem"; then \
		echo "✅ luafilesystem模块已安装"; \
	else \
		$(LUAROCKS) install --local luafilesystem && echo "✅ luafilesystem模块安装成功" || (echo "❌ luafilesystem模块安装失败" && exit 1); \
	fi

verify-deps:
	@echo "🔍 验证依赖安装..."
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) -e "require('cjson'); print('✅ cjson模块加载成功')" || (echo "❌ cjson模块加载失败" && exit 1)
	@echo "✅ 核心C模块依赖验证通过"

# =============================================================================
# 构建系统
# =============================================================================

# 创建目录结构
directories:
	@echo "📁 创建目录结构..."
	@mkdir -p $(BIN_DIR) $(LIB_DIR) $(LOGS_DIR) $(DATA_DIR)
	@mkdir -p $(TEST_DIR)/unit $(TEST_DIR)/integration $(TEST_DIR)/performance
	@mkdir -p $(EXAMPLES_DIR) $(DOCS_DIR) $(WEB_DIR)
	@echo "✅ 目录结构创建完成"

# 默认目标
all: directories install-deps verify-deps build
	@echo "✅ $(PROJECT_NAME) v$(VERSION) 构建完成"

# 构建项目
build: directories
	@echo "🔨 构建 $(PROJECT_NAME)..."
	@echo "📋 项目结构:"
	@echo "  - Lua模块目录: $(LUA_DIR)"
	@echo "  - 配置文件目录: $(CONF_DIR)"
	@echo "  - 数据目录: $(DATA_DIR)"
	@echo "  - 日志目录: $(LOGS_DIR)"
	@echo "  - Web目录: $(WEB_DIR)"
	@echo "✅ 构建完成"

# 安装项目
install: build
	@echo "📦 安装 $(PROJECT_NAME)..."
	@echo "✅ 安装完成"

# 快速构建（开发用）
dev-build: directories install-deps
	@echo "⚡ 快速构建（开发模式）..."
	@echo "✅ 开发构建完成"

build-micro-ts: directories
	@echo "🔨 编译 micro_ts.so..."
	@if [ -f $(SRC_DIR)/micro_ts.c ]; then \
		gcc -O2 -fPIC -shared -I$(LUA_INCDIR) $(SRC_DIR)/micro_ts.c -o $(LIB_DIR)/micro_ts.so; \
		echo "✅ micro_ts.so 编译完成"; \
	else \
		echo "⚠️  警告: 未找到 $(SRC_DIR)/micro_ts.c 文件"; \
	fi

# =============================================================================
# 测试系统
# =============================================================================

# 运行所有测试
test: test-core test-v3 test-cluster test-plugins test-csv test-api
	@echo "✅ 所有测试完成"

# 核心功能测试
test-core:
	@echo "🧪 运行核心功能测试..."
	@cd $(TEST_DIR) && LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) run_core_tests.lua
	@echo "✅ 核心功能测试完成"

# V3存储引擎测试
test-v3: test-v3-basic test-v3-integrated test-v3-comparison test-v3-validation
	@echo "✅ V3存储引擎测试完成"

test-v3-basic:
	@echo "🧪 运行V3基础版本测试..."
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) $(EXAMPLES_DIR)/v3/test_v3_basic.lua

test-v3-integrated:
	@echo "🧪 运行V3集成版本测试..."
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) $(EXAMPLES_DIR)/v3/test_v3_integrated.lua

test-v3-comparison:
	@echo "🧪 运行V3版本对比测试..."
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) $(EXAMPLES_DIR)/v3/test_v3_comparison.lua

test-v3-validation:
	@echo "🧪 运行V3版本功能验证..."
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) $(EXAMPLES_DIR)/v3/test_v3_validation.lua

# 集群测试
test-cluster: test-cluster-simple test-cluster-tsdb test-cluster-business
	@echo "✅ 集群测试完成"

test-cluster-simple:
	@echo "🧪 运行简单集群测试..."
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) $(TEST_DIR)/simple_cluster_test.lua

test-cluster-tsdb:
	@echo "🧪 运行TSDB集群测试..."
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) $(TEST_DIR)/tsdb_cluster_test.lua

test-cluster-business:
	@echo "🧪 运行业务集群测试..."
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) $(EXAMPLES_DIR)/business/test_business_cluster.lua

# 插件测试
test-plugins: test-cjson test-micro-ts
	@echo "✅ 插件测试完成"

test-cjson:
	@echo "🧪 测试 cjson.so 库功能..."
	@LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) -e "local cjson=require('cjson'); local t={name='dennis',age=18}; local s=cjson.encode(t); print(s); print(cjson.decode(s).name)"

test-micro-ts:
	@echo "🧪 测试 micro_ts 插件..."
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) $(LUA_DIR)/test_micro_ts_multi_version.lua

# CSV导入导出测试
test-csv:
	@echo "🧪 运行CSV导入导出测试..."
	@mkdir -p test_data
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) $(TEST_DIR)/csv_import_export_test.lua

# CSV导入导出压力测试
test-csv-stress: test-csv-stress-import test-csv-stress-export test-csv-stress-mixed
	@echo "✅ CSV压力测试完成"

test-csv-stress-import:
	@echo "🔥 运行CSV导入压力测试..."
	@chmod +x $(SCRIPTS_DIR)/dev/run-csv-stress-test.sh
	@$(SCRIPTS_DIR)/dev/run-csv-stress-test.sh --type import --threads 3 --requests 50 --duration 60

test-csv-stress-export:
	@echo "🔥 运行CSV导出压力测试..."
	@chmod +x $(SCRIPTS_DIR)/dev/run-csv-stress-test.sh
	@$(SCRIPTS_DIR)/dev/run-csv-stress-test.sh --type export --threads 3 --requests 50 --duration 60

test-csv-stress-mixed:
	@echo "🔥 运行CSV混合压力测试..."
	@chmod +x $(SCRIPTS_DIR)/dev/run-csv-stress-test.sh
	@$(SCRIPTS_DIR)/dev/run-csv-stress-test.sh --type mixed --threads 3 --requests 50 --duration 60

# CSV压力测试（完整版）
test-csv-stress-full:
	@echo "🔥 运行完整CSV压力测试..."
	@chmod +x $(SCRIPTS_DIR)/dev/run-csv-stress-test.sh
	@echo "=== CSV导入压力测试 ==="
	@$(SCRIPTS_DIR)/dev/run-csv-stress-test.sh --type import --threads 5 --requests 100 --duration 120
	@echo "=== CSV导出压力测试 ==="
	@$(SCRIPTS_DIR)/dev/run-csv-stress-test.sh --type export --threads 5 --requests 100 --duration 120
	@echo "=== CSV混合压力测试 ==="
	@$(SCRIPTS_DIR)/dev/run-csv-stress-test.sh --type mixed --threads 5 --requests 100 --duration 120
	@echo "✅ 完整CSV压力测试完成"

# CSV->LuaJIT->RocksDB数据流压力测试
test-csv-luajit-rocksdb: test-csv-luajit-rocksdb-quick test-csv-luajit-rocksdb-standard test-csv-luajit-rocksdb-stress
	@echo "✅ CSV->LuaJIT->RocksDB数据流压力测试完成"

test-csv-luajit-rocksdb-quick:
	@echo "⚡ 运行CSV->LuaJIT->RocksDB快速压力测试..."
	@chmod +x $(SCRIPTS_DIR)/dev/run-csv-luajit-rocksdb-stress-test.sh
	@$(SCRIPTS_DIR)/dev/run-csv-luajit-rocksdb-stress-test.sh -m quick

test-csv-luajit-rocksdb-standard:
	@echo "🔬 运行CSV->LuaJIT->RocksDB标准压力测试..."
	@chmod +x $(SCRIPTS_DIR)/dev/run-csv-luajit-rocksdb-stress-test.sh
	@$(SCRIPTS_DIR)/dev/run-csv-luajit-rocksdb-stress-test.sh -m standard

test-csv-luajit-rocksdb-stress:
	@echo "🔥 运行CSV->LuaJIT->RocksDB压力测试..."
	@chmod +x $(SCRIPTS_DIR)/dev/run-csv-luajit-rocksdb-stress-test.sh
	@$(SCRIPTS_DIR)/dev/run-csv-luajit-rocksdb-stress-test.sh -m stress

test-csv-luajit-rocksdb-full:
	@echo "🚀 运行CSV->LuaJIT->RocksDB完整压力测试..."
	@chmod +x $(SCRIPTS_DIR)/dev/run-csv-luajit-rocksdb-stress-test.sh
	@echo "=== 快速测试 ==="
	@$(SCRIPTS_DIR)/dev/run-csv-luajit-rocksdb-stress-test.sh -m quick
	@echo "=== 标准测试 ==="
	@$(SCRIPTS_DIR)/dev/run-csv-luajit-rocksdb-stress-test.sh -m standard
	@echo "=== 压力测试 ==="
	@$(SCRIPTS_DIR)/dev/run-csv-luajit-rocksdb-stress-test.sh -m stress
	@echo "✅ CSV->LuaJIT->RocksDB完整压力测试完成"

# API服务器测试
test-api:
	@echo "🌐 运行API服务器测试..."
	@cd $(TEST_DIR) && LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) test_api_server.lua

# 系统集成测试
test-integration:
	@echo "🔗 运行系统集成测试..."
	@cd $(TEST_DIR)/integration && LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) test_integration.lua

# 调试脚本测试
test-debug:
	@echo "🐛 运行调试脚本测试..."
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) debug_full_init.lua

# 快速测试（开发用）
test-quick: test-core test-v3-validation test-csv test-api
	@echo "✅ 快速测试完成"

# =============================================================================
# 服务管理
# =============================================================================

# 主系统启动
start:
	@echo "🚀 启动股票行情数据TSDB系统..."
	@chmod +x stock-tsdb
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" ./stock-tsdb start

start-daemon:
	@echo "🚀 后台启动股票行情数据TSDB系统..."
	@chmod +x stock-tsdb
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" ./stock-tsdb --daemon start &
	@echo "系统已启动，PID: $$!"

# Redis服务
redis-server:
	@echo "🚀 启动Redis集群服务器..."
	@cd $(LUA_DIR) && LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) start_redis_cluster.lua

redis-server-daemon:
	@echo "🚀 后台启动Redis集群服务器..."
	@cd $(LUA_DIR) && LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) start_redis_cluster.lua &
	@echo "Redis集群服务器已启动，PID: $$!"

redis-test:
	@echo "🧪 测试Redis集群服务器..."
	@echo "PING命令测试..."
	@(echo "PING"; sleep 0.1) | nc 127.0.0.1 6379 2>/dev/null && echo "✅ Redis服务正常" || echo "❌ Redis服务异常"

redis-stop:
	@echo "🛑 停止Redis集群服务器..."
	@pkill -f "start_redis_cluster.lua" || true
	@echo "✅ Redis集群服务器已停止"

# Web服务
web-server:
	@echo "🚀 启动元数据Web服务器..."
	@cd $(WEB_DIR) && LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) start_metadata_web.lua

web-server-daemon:
	@echo "🚀 后台启动元数据Web服务器..."
	@cd $(WEB_DIR) && LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) start_metadata_web.lua &
	@echo "元数据Web服务器已启动，PID: $$!"

web-test:
	@echo "🧪 测试Web服务器API..."
	@curl -s -I http://localhost:8080 2>/dev/null | head -1 | grep -q "200" && echo "✅ Web服务正常" || echo "❌ Web服务异常"

web-stop:
	@echo "🛑 停止Web服务器..."
	@pkill -f "start_metadata_web.lua" || true
	@echo "✅ Web服务器已停止"

# API服务器测试
api-server-test:
	@echo "🧪 测试API服务器..."
	@LUA_PATH="$(LUA_PATH)" LUA_CPATH="$(LUA_CPATH)" $(LUAJIT_BIN) test_api_server_fix.lua

# 开发环境
dev-start: redis-server-daemon web-server-daemon
	@echo "✅ 开发环境启动完成"
	@echo "服务信息:"
	@echo "  - Redis集群服务器: redis://localhost:6379"
	@echo "  - 元数据Web服务器: http://localhost:8080"

# 停止所有服务
stop-all:
	@echo "🛑 停止所有服务..."
	@pkill -f "main.lua" || true
	@pkill -f "start_redis_cluster.lua" || true
	@pkill -f "start_metadata_web.lua" || true
	@echo "✅ 所有服务已停止"

# 重启系统
restart: stop-all start-daemon
	@echo "🔄 系统重启完成"

# =============================================================================
# 项目验证
# =============================================================================

health-check:
	@echo "🔍 系统健康检查..."
	@which $(LUAJIT_BIN) > /dev/null && echo "✅ LuaJIT可用" || echo "❌ LuaJIT未找到"
	@which $(LUAROCKS) > /dev/null && echo "✅ LuaRocks可用" || echo "❌ LuaRocks未找到"
	@test -d $(LUA_DIR) && echo "✅ Lua模块目录存在" || echo "❌ Lua模块目录缺失"
	@test -d $(LIB_DIR) && echo "✅ 库文件目录存在" || echo "❌ 库文件目录缺失"
	@test -d $(DATA_DIR) && echo "✅ 数据目录存在" || echo "❌ 数据目录缺失"
	@echo "✅ 系统健康检查完成"

project-status:
	@echo "📊 项目状态检查..."
	@chmod +x $(SCRIPTS_DIR)/health-check.sh
	@./$(SCRIPTS_DIR)/health-check.sh --mode full

project-validate:
	@echo "✅ 项目完整性验证..."
	@chmod +x $(SCRIPTS_DIR)/validate_project.sh
	@./$(SCRIPTS_DIR)/validate_project.sh -c all -r

# =============================================================================
# 清理和维护
# =============================================================================

clean:
	@echo "🧹 清理构建文件..."
	@rm -rf $(BIN_DIR) $(LOGS_DIR)/* $(DATA_DIR)/*
	@echo "✅ 清理完成"

clean-all:
	@echo "🧹 深度清理..."
	@rm -rf $(BIN_DIR) $(LIB_DIR) $(LOGS_DIR) $(DATA_DIR)
	@find . -name "*.csv" -type f -delete
	@find . -name "*.log" -type f -delete
	@find . -name "*.tmp" -type f -delete
	@echo "✅ 深度清理完成"

# =============================================================================
# 帮助信息
# =============================================================================

help:
	@echo "Stock-TSDB 系统管理命令"
	@echo ""
	@echo "基本命令:"
	@echo "  make all                 - 完整构建项目（包含依赖安装和验证）"
	@echo "  make build               - 构建项目"
	@echo "  make dev-build           - 快速构建（开发模式）"
	@echo "  make test                - 运行所有测试"
	@echo "  make clean               - 清理构建文件"
	@echo "  make clean-all           - 深度清理项目"
	@echo "  make install-deps        - 安装依赖"
	@echo "  make verify-deps         - 验证依赖安装"
	@echo ""
	@echo "系统启动:"
	@echo "  make start               - 启动股票行情数据TSDB系统"
	@echo "  make start-daemon        - 后台启动系统"
	@echo "  make stop-all            - 停止所有服务"
	@echo "  make restart             - 重启系统"
	@echo ""
	@echo "测试命令:"
	@echo "  make test-core           - 运行核心功能测试"
	@echo "  make test-v3             - 运行V3存储引擎测试"
	@echo "  make test-cluster        - 运行集群测试"
	@echo "  make test-plugins        - 运行插件测试"
	@echo "  make test-csv            - 运行CSV导入导出测试"
	@echo "  make test-api            - 运行API服务器测试"
	@echo "  make test-integration    - 运行系统集成测试"
	@echo "  make test-debug          - 运行调试脚本测试"
	@echo "  make test-csv-stress     - 运行CSV压力测试"
	@echo "  make test-csv-stress-full - 运行完整CSV压力测试"
	@echo "  make test-csv-luajit-rocksdb - 运行CSV->LuaJIT->RocksDB数据流压力测试"
	@echo "  make test-csv-luajit-rocksdb-full - 运行完整CSV->LuaJIT->RocksDB压力测试"
	@echo "  make test-quick          - 快速测试（开发用）"
	@echo ""
	@echo "服务命令:"
	@echo "  make redis-server        - 启动Redis集群服务器"
	@echo "  make web-server           - 启动Web服务器"
	@echo "  make dev-start            - 启动开发环境"
	@echo "  make api-server-test      - 测试API服务器"
	@echo ""
	@echo "验证命令:"
	@echo "  make health-check         - 系统健康检查"
	@echo "  make project-status       - 项目状态检查"
	@echo "  make project-validate     - 项目完整性验证"
	@echo ""
	@echo "信息命令:"
	@echo "  make version              - 显示版本信息"
	@echo "  make tree                 - 显示目录结构"
	@echo "  make stats                - 显示文件统计"
	@echo ""
	@echo "更多信息请查看 README.md 文件"

# =============================================================================
# 特殊目标
# =============================================================================

# 显示版本信息
version:
	@echo "$(PROJECT_NAME) v$(VERSION)"
	@echo "平台: $(PLATFORM)"
	@echo "LuaJIT: $(shell $(LUAJIT_BIN) -v 2>/dev/null || echo '未安装')"
	@echo "LuaRocks: $(shell $(LUAROCKS) --version 2>/dev/null || echo '未安装')"

# 显示目录结构
tree:
	@echo "项目目录结构:"
	@tree -I '*.so|*.log|*.csv|*.tmp' -L 3

# 显示文件统计
stats:
	@echo "项目文件统计:"
	@echo "Lua文件: $(shell find $(LUA_DIR) -name '*.lua' | wc -l)"
	@echo "配置文件: $(shell find $(CONF_DIR) -name '*.conf' -o -name '*.json' | wc -l)"
	@echo "测试文件: $(shell find $(TEST_DIR) -name '*.lua' | wc -l)"
	@echo "文档文件: $(shell find $(DOCS_DIR) -name '*.md' | wc -l)"

# 默认目标
.DEFAULT_GOAL := help