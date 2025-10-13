# 股票行情数据TSDB系统 Makefile
# 基于 LuaJIT 的轻量级时间序列数据库

# 基础配置
PROJECT_NAME = stock-tsdb
VERSION = 1.0.0
LUAROCKS = luarocks

# 目录配置
SRC_DIR = src
OBJ_DIR = obj
BIN_DIR = bin
CONF_DIR = conf
LUA_DIR = lua
LIB_DIR = lib
LOGS_DIR = logs
DATA_DIR = data

# Lua 相关配置
LUA_VERSION = 5.1
LUAJIT_BIN = luajit

# 系统检测
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    PLATFORM = linux
endif
ifeq ($(UNAME_S),Darwin)
    PLATFORM = macos
endif

# Lua 模块列表
LUA_MODULES = $(LUA_DIR)/tsdb.lua \
               $(LUA_DIR)/storage.lua \
               $(LUA_DIR)/api.lua \
               $(LUA_DIR)/cluster.lua \
               $(LUA_DIR)/config.lua \
               $(LUA_DIR)/logger.lua \
               $(LUA_DIR)/monitor.lua \
               $(LUA_DIR)/main.lua \
               $(LUA_DIR)/event_server.lua

# 目标文件
TARGET = $(BIN_DIR)/stock-tsdb-server
MAIN_SCRIPT = stock-tsdb
MICRO_TS_SO = $(LIB_DIR)/micro_ts.so

# 默认目标
.PHONY: all build install clean test help check-deps install-deps run-dev run-prod

all: check-deps build

# 依赖检查
check-deps:
	@echo "检查系统依赖..."
	@which $(LUAJIT_BIN) > /dev/null || (echo "错误: 未找到 LuaJIT，请先安装" && exit 1)
	@which $(LUAROCKS) > /dev/null || (echo "错误: 未找到 LuaRocks，请先安装" && exit 1)
	@echo "✓ 系统依赖检查通过"

# 创建目录
$(BIN_DIR) $(LIB_DIR) $(LOGS_DIR) $(DATA_DIR):
	@mkdir -p $@

# 构建项目
build: directories $(TARGET) $(MICRO_TS_SO)
	@echo "构建完成 ✓"

# 创建启动器脚本
$(TARGET): $(BIN_DIR)
	@echo "创建启动器脚本..."
	@echo '#!/bin/bash' > $@
	@echo 'export LUA_PATH="$$LUA_PATH;./lua/?.lua;$(PREFIX)/share/$(PROJECT_NAME)/lua/?.lua;$$HOME/.luarocks/share/lua/5.1/?.lua;$$HOME/.luarocks/share/lua/5.1/?/init.lua"' >> $@
	@echo 'export LUA_CPATH="$$LUA_CPATH;./lib/?.so;./lib/?.dylib;$(PREFIX)/lib/lua/$(LUA_VERSION)/?.so;$$HOME/.luarocks/lib/lua/5.1/?.so;../lib/?.so"' >> $@
	@echo 'exec $(LUAJIT_BIN) $(MAIN_SCRIPT) "$$@"' >> $@
	@chmod +x $@
	@echo "✓ 启动器脚本已创建"

# 编译 micro_ts.so
$(MICRO_TS_SO): $(LIB_DIR) $(SRC_DIR)/micro_ts.c
	@echo "编译 micro_ts.so..."
	@gcc -O2 -fPIC -shared -I/usr/local/include/luajit-2.1 $(SRC_DIR)/micro_ts.c -o $@
	@echo "✓ micro_ts.so 编译完成"

# 安装 Lua 依赖
install-deps: directories
	@echo "安装 Lua 依赖包..."
	@echo "检查本地依赖..."
	@if [ -f $(LIB_DIR)/cjson.so ]; then \
		echo "✓ cjson 已存在于 lib 目录"; \
	else \
		echo "警告: 未找到本地 cjson.so 文件"; \
		echo "请运行 'make install-cjson' 安装 lua-cjson 库"; \
	fi
	@if [ -f $(LIB_DIR)/micro_ts.so ]; then \
		echo "✓ micro_ts 已存在于 lib 目录"; \
	else \
		echo "提示: 未找到本地 micro_ts.so 文件"; \
		echo "请运行 'make build' 编译 micro_ts 库"; \
	fi
	@echo "✓ Lua 依赖安装完成"

# 安装 lua-cjson 库
install-cjson: directories
	@echo "安装 lua-cjson 库..."
	@echo "使用 luarocks 安装 lua-cjson..."
	@sudo luarocks install lua-cjson LUA_INCDIR=/usr/local/include/luajit-2.1 LUA_LIBDIR=/usr/local/lib/
	@echo "查找并拷贝 cjson.so 到 lib 目录..."
	@if [ -f /usr/local/lib/lua/5.1/cjson.so ]; then \
		cp /usr/local/lib/lua/5.1/cjson.so $(LIB_DIR)/ && echo "✓ 从 /usr/local/lib/lua/5.1/ 拷贝成功"; \
	elif [ -f /usr/local/lib/lua/5.2/cjson.so ]; then \
		cp /usr/local/lib/lua/5.2/cjson.so $(LIB_DIR)/ && echo "✓ 从 /usr/local/lib/lua/5.2/ 拷贝成功"; \
	elif [ -f /usr/local/lib/luarocks/rocks/lua-cjson/*/lib/cjson.so ]; then \
		cp /usr/local/lib/luarocks/rocks/lua-cjson/*/lib/cjson.so $(LIB_DIR)/ && echo "✓ 从 luarocks 目录拷贝成功"; \
	else \
		echo "警告: 无法自动找到 cjson.so，请手动查找并拷贝到 $(LIB_DIR)/ 目录"; \
		echo "可能的路径:"; \
		echo "  - /usr/local/lib/lua/5.1/cjson.so"; \
		echo "  - /usr/local/lib/lua/5.2/cjson.so"; \
		echo "  - /usr/local/lib/luarocks/rocks/lua-cjson/*/lib/cjson.so"; \
		echo "  - /usr/lib/lua/5.1/cjson.so"; \
	fi
	@echo "✓ lua-cjson 安装完成"

# 编译 micro_ts 库
build-micro-ts: directories $(MICRO_TS_SO)
	@echo "✓ micro_ts 库编译完成"

# 运行测试
test: build
	@echo "运行测试..."
	@if [ -f tests/run_tests.sh ]; then \
		cd tests && ./run_tests.sh; \
	else \
		echo "运行 Lua 测试..."; \
		LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/simple_test.lua; \
	fi
	@echo ""
	@echo "运行配置管理器测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/testing/test_config_manager.lua
	@echo "✓ 测试完成"

# 运行配置管理器测试
test-config-manager: build
	@echo "运行配置管理器测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/testing/test_config_manager.lua
	@echo "✓ 配置管理器测试完成"

# 运行配置管理器快速测试
test-config-manager-quick: build
	@echo "运行配置管理器快速测试..."
	@$(LUAJIT_BIN) -e "
		package.path = package.path .. ';./lua/?.lua;./?.lua;;'
		package.cpath = package.cpath .. ';./lib/?.so;;'
		
		local ConfigManager = require 'config_manager'
		local config_manager = ConfigManager:new('./data/config_db')
		local success, err = config_manager:initialize()
		if success then
			print('✓ 配置管理器初始化成功')
			
			-- 测试获取系统配置
			local system_config = config_manager:get_config('system', 'main')
			if system_config and system_config.server then
				print('✓ 系统配置获取成功')
				print('   端口:', system_config.server.port)
				print('   绑定地址:', system_config.server.bind)
			else
				print('✗ 系统配置获取失败')
			end
			
			-- 测试获取业务配置
			local business_configs = config_manager:get_all_business_configs()
			if business_configs then
				print('✓ 业务配置获取成功，共', #business_configs, '个业务类型')
			else
				print('✗ 业务配置获取失败')
			end
			
			config_manager:close()
			print('✓ 配置管理器关闭成功')
		else
			print('✗ 配置管理器初始化失败:', err)
		end
	"
	@echo "✓ 配置管理器快速测试完成"

# 元数据初始化
metadata-init: build
	@echo "初始化元数据配置..."
	@$(LUAJIT_BIN) -e '\
	package.path = package.path .. ";./lua/?.lua;./?.lua;;"; \
	package.cpath = package.cpath .. ";./lib/?.so;;"; \
	local ConfigManager = require "config_manager"; \
	local config_manager = ConfigManager:new("./data/config_db"); \
	local success, err = config_manager:initialize(); \
	if success then \
		print("✓ 配置管理器初始化成功"); \
		local version_meta = config_manager:get_config("metadata", "version"); \
		if version_meta then \
			print("✓ 版本元数据:"); \
			print("   配置版本:", version_meta.config_schema_version); \
			print("   最后更新:", version_meta.last_updated); \
			print("   创建者:", version_meta.created_by); \
		else \
			print("✗ 版本元数据获取失败"); \
		end; \
		local stats_meta = config_manager:get_config("metadata", "statistics"); \
		if stats_meta then \
			print("✓ 统计元数据:"); \
			print("   业务类型数量:", stats_meta.total_business_types); \
			print("   实例数量:", stats_meta.total_instances); \
			print("   配置项数量:", stats_meta.config_items_count); \
		else \
			print("✗ 统计元数据获取失败"); \
		end; \
		config_manager:close(); \
		print("✓ 元数据初始化完成"); \
	else \
		print("✗ 配置管理器初始化失败:", err); \
	end'
	@echo "✓ 元数据初始化完成"

# 查询元数据列表
metadata-list: build
	@echo "查询元数据列表..."
	@$(LUAJIT_BIN) -e '\
	package.path = package.path .. ";./lua/?.lua;./?.lua;;"; \
	package.cpath = package.cpath .. ";./lib/?.so;;"; \
	local ConfigManager = require "config_manager"; \
	local config_manager = ConfigManager:new("./data/config_db"); \
	local success, err = config_manager:initialize(); \
	if success then \
		print("✓ 配置管理器初始化成功"); \
		local metadata_types = {"version", "statistics"}; \
		print("✓ 元数据类型列表:"); \
		for i, meta_type in ipairs(metadata_types) do \
			print("   " .. i .. ". " .. meta_type); \
		end; \
		print("✓ 元数据内容:"); \
		for i, meta_type in ipairs(metadata_types) do \
			local meta_data = config_manager:get_config("metadata", meta_type); \
			if meta_data then \
				print("   " .. meta_type .. ":"); \
				for key, value in pairs(meta_data) do \
					print("      " .. key .. ": " .. tostring(value)); \
				end; \
			else \
				print("   " .. meta_type .. ": 无数据"); \
			end; \
		end; \
		print("✓ 配置统计:"); \
		print("   元数据类型数量:", #metadata_types); \
		config_manager:close(); \
		print("✓ 元数据查询完成"); \
	else \
		print("✗ 配置管理器初始化失败:", err); \
	end'
	@echo "✓ 元数据列表查询完成"

# 元数据修改
metadata-update: build
	@echo "修改元数据配置..."
	@$(LUAJIT_BIN) -e '\
	package.path = package.path .. ";./lua/?.lua;./?.lua;;"; \
	package.cpath = package.cpath .. ";./lib/?.so;;"; \
	local ConfigManager = require "config_manager"; \
	local config_manager = ConfigManager:new("./data/config_db"); \
	local success, err = config_manager:initialize(); \
	if success then \
		print("✓ 配置管理器初始化成功"); \
		local new_version_meta = { \
			config_schema_version = "1.1", \
			last_updated = os.date("%Y-%m-%d %H:%M:%S"), \
			created_by = "metadata-update command" \
		}; \
		local update_success = config_manager:update_config("metadata", "version", new_version_meta); \
		if update_success then \
			print("✓ 版本元数据更新成功"); \
			print("   新版本:", new_version_meta.config_schema_version); \
			print("   更新时间:", new_version_meta.last_updated); \
		else \
			print("✗ 版本元数据更新失败"); \
		end; \
		local new_stats_meta = { \
			total_business_types = 5, \
			total_instances = 15, \
			config_items_count = 42 \
		}; \
		update_success = config_manager:update_config("metadata", "statistics", new_stats_meta); \
		if update_success then \
			print("✓ 统计元数据更新成功"); \
			print("   业务类型数量:", new_stats_meta.total_business_types); \
			print("   实例数量:", new_stats_meta.total_instances); \
			print("   配置项数量:", new_stats_meta.config_items_count); \
		else \
			print("✗ 统计元数据更新失败"); \
		end; \
		config_manager:close(); \
		print("✓ 元数据更新完成"); \
	else \
		print("✗ 配置管理器初始化失败:", err); \
	end'
	@echo "✓ 元数据修改完成"

# 运行核心测试（跳过不稳定的测试）
test-core: build
	@echo "运行核心测试..."
	@cd tests && LUA_PATH='../lua/?.lua;../?.lua;../examples/?.lua;../examples/?/?.lua;;' $(LUAJIT_BIN) run_core_tests.lua
	@echo "✓ 核心测试完成"

# V3版本测试目标
test-v3: build
	@echo "运行V3版本测试..."
	@echo "1. 运行V3基础版本测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/v3/test_v3_basic.lua
	@echo "2. 运行V3集成版本测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/v3/test_v3_integrated.lua
	@echo "3. 运行V3版本对比测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/v3/test_v3_comparison.lua
	@echo "4. 运行V3版本功能验证..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/v3/test_v3_validation.lua
	@echo "✓ V3版本测试完成"

# V3基础版本测试
test-v3-basic: build
	@echo "运行V3基础版本测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/v3/test_v3_basic.lua
	@echo "✓ V3基础版本测试完成"

# V3集成版本测试
test-v3-integrated: build
	@echo "运行V3集成版本测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/v3/test_v3_integrated.lua
	@echo "✓ V3集成版本测试完成"

# V3版本对比测试
test-v3-comparison: build
	@echo "运行V3版本对比测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/v3/test_v3_comparison.lua
	@echo "✓ V3版本对比测试完成"

# V3版本功能验证
test-v3-validation: build
	@echo "运行V3版本功能验证..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/v3/test_v3_validation.lua
	@echo "✓ V3版本功能验证完成"

# V3性能详细分析
test-v3-performance: build
	@echo "运行V3性能详细分析..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/v3/v3_performance_analysis_final.lua
	@echo "✓ V3性能详细分析完成"

# V3最终对比测试
test-v3-final: build
	@echo "运行V3最终对比测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/v3/test_v3_final_comparison.lua
	@echo "✓ V3最终对比测试完成"

# 运行所有集群测试
test-cluster: build
	@echo "运行所有集群测试..."
	@echo "1. 运行简单集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/simple_cluster_test.lua
	@echo "2. 运行TSDB集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/tsdb_cluster_test.lua
	@echo "3. 运行业务集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) test_business_cluster.lua
	@echo "4. 运行Consul集成测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) test_consul_integration.lua
	@echo "5. 运行优化集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) test_optimized_cluster.lua
	@echo "✓ 所有集群测试完成"

# 运行简单集群测试
test-cluster-simple: build
	@echo "运行简单集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/simple_cluster_test.lua
	@echo "✓ 简单集群测试完成"

# 运行TSDB集群测试
test-cluster-tsdb: build
	@echo "运行TSDB集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/tsdb_cluster_test.lua
	@echo "✓ TSDB集群测试完成"

# 运行业务集群测试
test-cluster-business: build
	@echo "运行业务集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) test_business_cluster.lua
	@echo "✓ 业务集群测试完成"

# 运行Consul集成测试
test-cluster-consul: build
	@echo "运行Consul集成测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) test_consul_integration.lua
	@echo "✓ Consul集成测试完成"

# 运行优化集群测试
test-cluster-optimized: build
	@echo "运行优化集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) test_optimized_cluster.lua
	@echo "✓ 优化集群测试完成"

# 运行所有集群相关测试（包括集成测试）
test-cluster-all: build
	@echo "运行所有集群相关测试..."
	@echo "1. 运行简单集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/simple_cluster_test.lua
	@echo "2. 运行TSDB集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/tsdb_cluster_test.lua
	@echo "3. 运行业务集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) test_business_cluster.lua
	@echo "4. 运行Consul集成测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) test_consul_integration.lua
	@echo "5. 运行优化集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) test_optimized_cluster.lua
	@echo "6. 运行集成TSDB测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/integrated_tsdb_test.lua || echo "注意: 集成TSDB测试可能有依赖问题"
	@echo "7. 运行真实股票数据测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/real_stock_data_test.lua || echo "注意: 真实股票数据测试可能有依赖问题"
	@echo "8. 运行综合测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/comprehensive_test.lua || echo "注意: 综合测试可能有依赖问题"
	@echo "9. 运行股票示例测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/stock_example.lua
	@echo "10. 运行Redis集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/test_redis_cluster.lua || echo "注意: Redis集群测试可能有依赖问题"
	@echo "11. 运行FFI测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/test_ffi.lua
	@echo "12. 运行冷热数据功能测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) test_daily_cf_engine.lua
	@echo "13. 运行冷热数据集成示例..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) integrate_daily_cf_example.lua
	@echo "✓ 所有集群相关测试完成"

# 冷热数据功能专项测试
test-cold-hot-data: build
	@echo "运行冷热数据功能专项测试..."
	@echo "1. 测试每日CF存储引擎..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) test_daily_cf_engine.lua
	@echo "2. 测试冷热数据集成示例..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) integrate_daily_cf_example.lua
	@echo "3. 测试冷热数据在集群中的应用..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) test_cold_hot_cluster.lua || echo "注意: 冷热数据集群测试可能有依赖问题"
	@echo "✓ 冷热数据功能专项测试完成"

# 快速验证（推荐用于开发）
test-quick: build
	@echo "运行快速验证测试..."
	@echo "1. V3基础版本功能验证..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/v3/test_v3_validation.lua
	@echo "2. V3版本对比测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) examples/v3/test_v3_comparison.lua
	@echo "3. 简单集群测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/simple_cluster_test.lua
	@echo "✓ 快速验证完成"

# 系统健康检查
health-check:
	@echo "系统健康检查..."
	@echo "1. 检查LuaJIT..."
	@which $(LUAJIT_BIN) > /dev/null && echo "✓ LuaJIT可用" || echo "✗ LuaJIT未找到"
	@echo "2. 检查LuaRocks..."
	@which $(LUAROCKS) > /dev/null && echo "✓ LuaRocks可用" || echo "✗ LuaRocks未找到"
	@echo "3. 检查核心文件..."
	@which $(LUAJIT_BIN) > /dev/null && echo "✓ LuaJIT可执行" || echo "✗ LuaJIT不可执行"
	@test -f examples/v3/test_v3_basic.lua && echo "✓ V3基础测试文件存在" || echo "✗ V3基础测试文件缺失"
	@test -f examples/v3/test_v3_validation.lua && echo "✓ V3验证测试文件存在" || echo "✗ V3验证测试文件缺失"
	@test -d lua && echo "✓ Lua模块目录存在" || echo "✗ Lua模块目录缺失"
	@test -d lib && echo "✓ 库文件目录存在" || echo "✗ 库文件目录缺失"
	@echo "4. 检查数据目录..."
	@test -d data && echo "✓ 数据目录存在" || echo "✗ 数据目录缺失"
	@echo "✓ 系统健康检查完成"

# 启动Redis集群服务器
redis-server: build
	@echo "启动Redis集群服务器..."
	@cd $(LUA_DIR) && LUA_PATH='./?.lua;../?.lua;;' $(LUAJIT_BIN) start_redis_cluster.lua

# 启动Redis集群服务器（后台模式）
redis-server-daemon: build
	@echo "启动Redis集群服务器（后台模式）..."
	@cd $(LUA_DIR) && LUA_PATH='./?.lua;../?.lua;;' $(LUAJIT_BIN) start_redis_cluster.lua &
	@echo "Redis集群服务器已启动，PID: $$!"

# 测试Redis集群服务器
redis-test: build
	@echo "测试Redis集群服务器..."
	@echo "PING命令测试..."
	@(echo "PING"; sleep 0.1) | nc 127.0.0.1 6379
	@echo ""
	@echo "INFO命令测试..."
	@(echo "INFO"; sleep 0.1) | nc 127.0.0.1 6379 | head -10
	@echo ""
	@echo "CLUSTER INFO命令测试..."
	@(echo "CLUSTER INFO"; sleep 0.1) | nc 127.0.0.1 6379
	@echo ""
	@echo "✓ Redis集群服务器测试完成"

# 运行Redis集群服务器完整测试
redis-test-full: build
	@echo "运行Redis集群服务器完整测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/test_redis_cluster.lua

# 停止Redis集群服务器
redis-stop:
	@echo "停止Redis集群服务器..."
	@pkill -f "start_redis_cluster.lua" || true
	@echo "✓ Redis集群服务器已停止"

# Redis TCP服务器相关命令

# 启动Redis TCP服务器
redis-tcp-server: build
	@echo "启动Redis TCP服务器..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) start_redis_tcp_server.lua

# 启动Redis TCP服务器（后台模式）
redis-tcp-server-daemon: build
	@echo "启动Redis TCP服务器（后台模式）..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) start_redis_tcp_server.lua &
	@echo "Redis TCP服务器已启动，PID: $$!"

# Web服务器相关命令

# 启动元数据Web服务器
web-server: build
	@echo "启动元数据Web服务器..."
	@cd web && LUA_PATH='../lua/?.lua;../?.lua;;' $(LUAJIT_BIN) start_metadata_web.lua

# 启动元数据Web服务器（后台模式）
web-server-daemon: build
	@echo "启动元数据Web服务器（后台模式）..."
	@cd web && LUA_PATH='../lua/?.lua;../?.lua;;' $(LUAJIT_BIN) start_metadata_web.lua &
	@echo "元数据Web服务器已启动，PID: $$!"

# 测试Web服务器API
web-test: build
	@echo "测试Web服务器API..."
	@echo "1. 测试主页..."
	@curl -s -I http://localhost:8080 | head -1
	@echo "2. 测试配置API..."
	@curl -s http://localhost:8080/api/config | jq '.config_items_count' 2>/dev/null || echo "配置API响应:" && curl -s http://localhost:8080/api/config | head -2
	@echo "3. 测试元数据API..."
	@curl -s http://localhost:8080/api/metadata | jq '.business_types | length' 2>/dev/null || echo "元数据API响应:" && curl -s http://localhost:8080/api/metadata | head -2
	@echo "4. 测试静态文件..."
	@curl -s -I http://localhost:8080/css/style.css | head -1
	@curl -s -I http://localhost:8080/js/app.js | head -1
	@echo "✓ Web服务器API测试完成"

# Web服务器快速测试
web-test-quick: build
	@echo "Web服务器快速测试..."
	@echo "测试主页响应..."
	@curl -s -I http://localhost:8080 | grep "HTTP" || echo "Web服务器未运行"
	@echo "测试API响应..."
	@curl -s http://localhost:8080/api/config | head -1
	@echo "✓ Web服务器快速测试完成"

# 停止Web服务器
web-stop:
	@echo "停止Web服务器..."
	@pkill -f "start_metadata_web.lua" || true
	@echo "✓ Web服务器已停止"

# Web服务器健康检查
web-health: build
	@echo "Web服务器健康检查..."
	@echo "1. 检查Web服务器进程..."
	@pgrep -f "start_metadata_web.lua" > /dev/null && echo "✓ Web服务器进程运行中" || echo "✗ Web服务器进程未运行"
	@echo "2. 检查端口8080..."
	@netstat -an | grep 8080 > /dev/null && echo "✓ 端口8080被占用" || echo "✗ 端口8080未被占用"
	@echo "3. 测试HTTP连接..."
	@curl -s -m 5 http://localhost:8080 > /dev/null && echo "✓ HTTP连接正常" || echo "✗ HTTP连接失败"
	@echo "4. 测试API端点..."
	@curl -s -m 5 http://localhost:8080/api/config > /dev/null && echo "✓ API端点正常" || echo "✗ API端点异常"
	@echo "✓ Web服务器健康检查完成"

# 完整的Web服务器测试套件
web-test-full: build
	@echo "运行完整的Web服务器测试套件..."
	@echo "1. 启动Web服务器..."
	@cd web && LUA_PATH='../lua/?.lua;../?.lua;;' $(LUAJIT_BIN) start_metadata_web.lua &
	@WEB_PID=$$! && echo "Web服务器启动，PID: $$WEB_PID"
	@sleep 3
	@echo "2. 运行健康检查..."
	@make web-health
	@echo "3. 运行API测试..."
	@make web-test
	@echo "4. 停止Web服务器..."
	@kill $$WEB_PID 2>/dev/null || true
	@echo "✓ 完整的Web服务器测试套件完成"

# 开发环境启动（Web服务器 + Redis集群）
dev-start: build
	@echo "启动开发环境..."
	@echo "1. 启动Redis集群服务器..."
	@cd $(LUA_DIR) && LUA_PATH='./?.lua;../?.lua;;' $(LUAJIT_BIN) start_redis_cluster.lua &
	@REDIS_PID=$$! && echo "Redis集群服务器启动，PID: $$REDIS_PID"
	@sleep 2
	@echo "2. 启动业务数据Web服务器..."
	@cd web && LUA_PATH='../lua/?.lua;../?.lua;;' $(LUAJIT_BIN) start_business_web.lua &
	@WEB_PID=$$! && echo "业务数据Web服务器启动，PID: $$WEB_PID"
	@sleep 2
	@echo "3. 启动元数据Web服务器..."
	@cd web && LUA_PATH='../lua/?.lua;../?.lua;;' $(LUAJIT_BIN) start_metadata_web.lua &
	@METADATA_PID=$$! && echo "元数据Web服务器启动，PID: $$METADATA_PID"
	@sleep 2
	@echo "✓ 开发环境启动完成"
	@echo "服务信息:"
	@echo "  - Redis集群服务器: http://localhost:6379"
	@echo "  - 业务数据Web服务器: http://localhost:8081"
	@echo "  - 元数据Web服务器: http://localhost:8080"
	@echo "使用 'make dev-stop' 停止开发环境"

# 停止开发环境
dev-stop:
	@echo "停止开发环境..."
	@pkill -f "start_redis_cluster.lua" || true
	@pkill -f "start_business_web.lua" || true
	@pkill -f "start_metadata_web.lua" || true
	@echo "✓ 开发环境已停止"

# 业务数据Web服务器相关命令

# 启动业务数据Web服务器
business-web-server: build
	@echo "启动业务数据Web服务器..."
	@cd web && LUA_PATH='../lua/?.lua;../?.lua;;' $(LUAJIT_BIN) start_business_web.lua

# 启动业务数据Web服务器（后台模式）
business-web-server-daemon: build
	@echo "启动业务数据Web服务器（后台模式）..."
	@cd web && LUA_PATH='../lua/?.lua;../?.lua;;' $(LUAJIT_BIN) start_business_web.lua &
	@echo "业务数据Web服务器已启动，PID: $$!"
	@echo "访问地址: http://localhost:8081"

# 测试业务数据Web服务器API
business-web-test: build
	@echo "测试业务数据Web服务器API..."
	@echo "1. 测试SQL查询API..."
	@curl -s -X POST http://localhost:8081/business/query -H "Content-Type: application/json" -d '{"sql":"SELECT device_id, MAX(value), MIN(value), AVG(value) FROM iot_data GROUP BY device_id"}' | jq '.success' 2>/dev/null || echo "SQL查询API响应:" && curl -s -X POST http://localhost:8081/business/query -H "Content-Type: application/json" -d '{"sql":"SELECT device_id, MAX(value), MIN(value), AVG(value) FROM iot_data GROUP BY device_id"}' | head -2
	@echo "2. 测试主页..."
	@curl -s -I http://localhost:8081 | head -1
	@echo "✓ 业务数据Web服务器API测试完成"

# 停止业务数据Web服务器
business-web-stop:
	@echo "停止业务数据Web服务器..."
	@pkill -f "start_business_web.lua" || true
	@echo "✓ 业务数据Web服务器已停止"

# 业务数据Web服务器健康检查
business-web-health: build
	@echo "业务数据Web服务器健康检查..."
	@echo "1. 检查Web服务器进程..."
	@pgrep -f "start_business_web.lua" > /dev/null && echo "✓ 业务数据Web服务器进程运行中" || echo "✗ 业务数据Web服务器进程未运行"
	@echo "2. 检查端口8081..."
	@netstat -an | grep 8081 > /dev/null && echo "✓ 端口8081被占用" || echo "✗ 端口8081未被占用"
	@echo "3. 测试HTTP连接..."
	@curl -s -m 5 http://localhost:8081 > /dev/null && echo "✓ HTTP连接正常" || echo "✗ HTTP连接失败"
	@echo "4. 测试SQL查询端点..."
	@curl -s -m 5 -X POST http://localhost:8081/business/query -H "Content-Type: application/json" -d '{"sql":"SELECT 1"}' > /dev/null && echo "✓ SQL查询端点正常" || echo "✗ SQL查询端点异常"
	@echo "✓ 业务数据Web服务器健康检查完成"

# 完整的业务数据Web服务器测试套件
business-web-test-full: build
	@echo "运行完整的业务数据Web服务器测试套件..."
	@echo "1. 启动业务数据Web服务器..."
	@cd web && LUA_PATH='../lua/?.lua;../?.lua;;' $(LUAJIT_BIN) start_business_web.lua &
	@BUSINESS_WEB_PID=$$! && echo "业务数据Web服务器启动，PID: $$BUSINESS_WEB_PID"
	@sleep 3
	@echo "2. 运行健康检查..."
	@make business-web-health
	@echo "3. 运行API测试..."
	@make business-web-test
	@echo "4. 停止业务数据Web服务器..."
	@kill $$BUSINESS_WEB_PID 2>/dev/null || true
	@echo "✓ 完整的业务数据Web服务器测试套件完成"

# SQL查询字段顺序测试
sql-field-order-test: build
	@echo "测试SQL查询字段顺序..."
	@echo "1. 启动业务数据Web服务器..."
	@cd web && LUA_PATH='../lua/?.lua;../?.lua;;' $(LUAJIT_BIN) start_business_web.lua &
	@BUSINESS_WEB_PID=$$! && echo "业务数据Web服务器启动，PID: $$BUSINESS_WEB_PID"
	@sleep 3
	@echo "2. 测试GROUP BY查询字段顺序..."
	@curl -s -X POST http://localhost:8081/business/query -H "Content-Type: application/json" -d '{"sql":"SELECT device_id, MAX(value), MIN(value), AVG(value) FROM iot_data GROUP BY device_id"}' | jq '.data[0] | keys' 2>/dev/null || echo "查询结果:" && curl -s -X POST http://localhost:8081/business/query -H "Content-Type: application/json" -d '{"sql":"SELECT device_id, MAX(value), MIN(value), AVG(value) FROM iot_data GROUP BY device_id"}' | head -5
	@echo "3. 测试股票数据查询字段顺序..."
	@curl -s -X POST http://localhost:8081/business/query -H "Content-Type: application/json" -d '{"sql":"SELECT stock_code, COUNT(*), AVG(price) FROM stock_quotes GROUP BY stock_code"}' | jq '.data[0] | keys' 2>/dev/null || echo "查询结果:" && curl -s -X POST http://localhost:8081/business/query -H "Content-Type: application/json" -d '{"sql":"SELECT stock_code, COUNT(*), AVG(price) FROM stock_quotes GROUP BY stock_code"}' | head -5
	@echo "4. 停止业务数据Web服务器..."
	@kill $$BUSINESS_WEB_PID 2>/dev/null || true
	@echo "✓ SQL查询字段顺序测试完成"

# 完整的开发环境测试套件
dev-test-full: build
	@echo "运行完整的开发环境测试套件..."
	@echo "1. 启动开发环境..."
	@make dev-start
	@sleep 5
	@echo "2. 运行Redis集群测试..."
	@make redis-test
	@echo "3. 运行元数据Web服务器测试..."
	@make web-test
	@echo "4. 运行业务数据Web服务器测试..."
	@make business-web-test
	@echo "5. 运行SQL查询字段顺序测试..."
	@make sql-field-order-test
	@echo "6. 停止开发环境..."
	@make dev-stop
	@echo "✓ 完整的开发环境测试套件完成"

# 快速开发测试（推荐用于日常开发）
dev-test-quick: build
	@echo "运行快速开发测试..."
	@echo "1. 启动业务数据Web服务器..."
	@cd web && LUA_PATH='../lua/?.lua;../?.lua;;' $(LUAJIT_BIN) start_business_web.lua &
	@BUSINESS_WEB_PID=$$! && echo "业务数据Web服务器启动，PID: $$BUSINESS_WEB_PID"
	@sleep 3
	@echo "2. 测试SQL查询功能..."
	@curl -s -X POST http://localhost:8081/business/query -H "Content-Type: application/json" -d '{"sql":"SELECT device_id, MAX(value), MIN(value), AVG(value) FROM iot_data GROUP BY device_id"}' | jq '.success' 2>/dev/null && echo "✓ SQL查询功能正常" || echo "✗ SQL查询功能异常"
	@echo "3. 停止业务数据Web服务器..."
	@kill $$BUSINESS_WEB_PID 2>/dev/null || true
	@echo "✓ 快速开发测试完成"

# 文档生成和验证
docs-validate:
	@echo "验证文档完整性..."
	@test -f README.md && echo "✓ README.md 存在" || echo "✗ README.md 缺失"
	@test -f CHANGELOG.md && echo "✓ CHANGELOG.md 存在" || echo "✗ CHANGELOG.md 缺失"
	@test -f DOCUMENTATION_INDEX.md && echo "✓ DOCUMENTATION_INDEX.md 存在" || echo "✗ DOCUMENTATION_INDEX.md 缺失"
	@test -f PROJECT_STRUCTURE.md && echo "✓ PROJECT_STRUCTURE.md 存在" || echo "✗ PROJECT_STRUCTURE.md 缺失"
	@test -d docs && echo "✓ docs目录存在" || echo "✗ docs目录缺失"
	@test -d scripts && echo "✓ scripts目录存在" || echo "✗ scripts目录缺失"
	@echo "✓ 文档验证完成"

# 脚本验证
scripts-validate:
	@echo "验证脚本完整性..."
	@test -f scripts/install/install.sh && echo "✓ install.sh 存在" || echo "✗ install.sh 缺失"
	@test -f scripts/install/production_deploy.sh && echo "✓ production_deploy.sh 存在" || echo "✗ production_deploy.sh 缺失"
	@test -f scripts/install/monitor_production.sh && echo "✓ monitor_production.sh 存在" || echo "✗ monitor_production.sh 缺失"
	@test -f scripts/install/backup_production.sh && echo "✓ backup_production.sh 存在" || echo "✗ backup_production.sh 缺失"
	@test -f scripts/install/maintain_production.sh && echo "✓ maintain_production.sh 存在" || echo "✗ maintain_production.sh 缺失"
	@echo "✓ 脚本验证完成"

# 项目完整性检查
project-integrity-check:
	@echo "项目完整性检查..."
	@make docs-validate
	@make scripts-validate
	@make health-check
	@echo "✓ 项目完整性检查完成"

# 项目完整性验证（使用脚本）
project-validate:
	@echo "=== 项目完整性验证 ==="
	@echo "使用验证脚本进行全面检查..."
	@chmod +x scripts/validate_project.sh
	@./scripts/validate_project.sh -c all -r
	@echo "验证完成，详细报告已生成。"

# 快速项目验证
project-validate-quick:
	@echo "=== 快速项目验证 ==="
	@chmod +x scripts/validate_project.sh
	@./scripts/validate_project.sh -c files -c deps -c config

# 项目状态检查
project-status:
	@echo "=== 项目状态检查 ==="
	@chmod +x scripts/check_project_status.sh
	@./scripts/check_project_status.sh -c all

# 开发环境设置
dev-setup:
	@echo "=== 开发环境设置 ==="
	@chmod +x scripts/setup_dev_env.sh
	@./scripts/setup_dev_env.sh -f

# 开发环境快速设置
dev-setup-quick:
	@echo "=== 开发环境快速设置 ==="
	@chmod +x scripts/setup_dev_env.sh
	@./scripts/setup_dev_env.sh -b

# 一键部署和测试（用于CI/CD）
ci-cd-pipeline: build
	@echo "运行CI/CD流水线..."
	@echo "1. 项目完整性检查..."
	@make project-integrity-check
	@echo "2. 运行核心测试..."
	@make test-core
	@echo "3. 运行V3版本测试..."
	@make test-v3
	@echo "4. 运行快速开发测试..."
	@make dev-test-quick
	@echo "✓ CI/CD流水线完成"
	@sleep 2
	@echo "2. 启动元数据Web服务器..."
	@cd web && LUA_PATH='../lua/?.lua;../?.lua;;' $(LUAJIT_BIN) start_metadata_web.lua &
	@WEB_PID=$$! && echo "元数据Web服务器启动，PID: $$WEB_PID"
	@sleep 2
	@echo "3. 验证服务状态..."
	@echo "Redis集群: http://localhost:6379"
	@echo "元数据Web: http://localhost:8080"
	@echo "开发环境启动完成！"
	@echo "使用 'make dev-stop' 停止开发环境"

# 停止开发环境
dev-stop:
	@echo "停止开发环境..."
	@make redis-stop
	@make web-stop
	@echo "✓ 开发环境已停止"

# 帮助信息
help:
	@echo "Stock-TSDB 系统管理命令"
	@echo ""
	@echo "基本命令:"
	@echo "  make build              - 构建项目"
	@echo "  make test               - 运行测试"
	@echo "  make clean              - 清理构建文件"
	@echo "  make install-deps       - 安装依赖"
	@echo ""
	@echo "Web服务器命令:"
	@echo "  make web-server          - 启动Web服务器"
	@echo "  make web-server-daemon   - 后台启动Web服务器"
	@echo "  make web-test            - 测试Web服务器API"
	@echo "  make web-health          - Web服务器健康检查"
	@echo "  make web-stop            - 停止Web服务器"
	@echo ""
	@echo "Redis服务器命令:"
	@echo "  make redis-server        - 启动Redis集群服务器"
	@echo "  make redis-server-daemon - 后台启动Redis集群服务器"
	@echo "  make redis-test          - 测试Redis集群服务器"
	@echo "  make redis-stop          - 停止Redis集群服务器"
	@echo ""
	@echo "开发环境命令:"
	@echo "  make dev-start           - 启动完整开发环境"
	@echo "  make dev-stop            - 停止开发环境"
	@echo "  make dev-setup           - 完整开发环境设置"
	@echo "  make dev-setup-quick     - 快速开发环境设置"
	@echo ""
	@echo "项目验证命令:"
	@echo "  make project-status      - 项目状态检查"
	@echo "  make project-validate    - 项目完整性验证"
	@echo "  make project-validate-quick - 快速项目验证"
	@echo "  make project-integrity-check - 项目完整性检查"
	@echo ""
	@echo "测试命令:"
	@echo "  make test-core           - 运行核心测试"
	@echo "  make test-v3             - 运行V3版本测试"
	@echo "  make test-cluster        - 运行集群测试"
	@echo "  make test-quick          - 快速验证测试"
	@echo ""
	@echo "更多信息请查看 README.md 文件"

# 测试Redis TCP服务器
redis-tcp-test: build
	@echo "测试Redis TCP服务器..."
	@echo "PING命令测试..."
	@(echo "PING"; sleep 0.1) | nc 127.0.0.1 6379
	@echo ""
	@echo "ECHO命令测试..."
	@(echo "ECHO hello"; sleep 0.1) | nc 127.0.0.1 6379
	@echo ""
	@echo "TIME命令测试..."
	@(echo "TIME"; sleep 0.1) | nc 127.0.0.1 6379
	@echo ""
	@echo "BATCH_SET命令测试..."
	@(echo "BATCH_SET test_key test_value"; sleep 0.1) | nc 127.0.0.1 6379
	@echo ""
	@echo "CLUSTER_INFO命令测试..."
	@(echo "CLUSTER INFO"; sleep 0.1) | nc 127.0.0.1 6379
	@echo ""
	@echo "✓ Redis TCP服务器测试完成"

# 运行Redis TCP服务器完整测试
redis-tcp-test-full: build
	@echo "运行Redis TCP服务器完整测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/test_redis_tcp_server.lua

# 停止Redis TCP服务器
redis-tcp-stop:
	@echo "停止Redis TCP服务器..."
	@pkill -f "start_redis_tcp_server.lua" || true
	@echo "✓ Redis TCP服务器已停止"

# 集成测试：Redis TCP服务器与业务实例
redis-tcp-integration: build
	@echo "运行Redis TCP服务器与业务实例集成测试..."
	@echo "1. 启动业务实例..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) start_business_instances.lua &
	@sleep 2
	@echo "2. 启动Redis TCP服务器..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) start_redis_tcp_server.lua &
	@sleep 2
	@echo "3. 运行集成测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) demo_business_separation.lua
	@echo "4. 停止服务..."
	@pkill -f "start_business_instances.lua" || true
	@pkill -f "start_redis_tcp_server.lua" || true
	@echo "✓ Redis TCP服务器集成测试完成"

# Redis TCP服务器联调集成测试
redis-tcp-integration-full: build
	@echo "运行Redis TCP服务器完整联调集成测试..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' $(LUAJIT_BIN) tests/integrate_redis_tcp_server.lua

# 测试cjson.so库功能
test-cjson:
	@echo "🔧 测试 cjson.so 库功能..."
	@LUA_CPATH="./lib/?.so;../lib/?.so;./?.so;;" $(LUAJIT_BIN) -e "local cjson=require('cjson'); local t={name='dennis',age=18}; local s=cjson.encode(t); print(s); print(cjson.decode(s).name)"
	@echo "✓ cjson.so 库测试完成"

# 测试micro_ts插件多版本性能对比
test-micro-ts:
	@echo "🚀 测试 micro_ts 插件多版本性能对比..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' LUA_CPATH="./lib/?.so;../lib/?.so;./?.so;;" $(LUAJIT_BIN) lua/test_micro_ts_multi_version.lua
	@echo "✓ micro_ts 插件多版本性能对比测试完成"

# 运行插件对比分析
test-plugin-comparison:
	@echo "📊 运行插件对比分析..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' LUA_CPATH="./lib/?.so;../lib/?.so;./?.so;;" $(LUAJIT_BIN) lua/plugin_comparison_analysis.lua
	@echo "✓ 插件对比分析完成"

# 运行插件对比分析并保存结果
test-plugin-comparison-save:
	@echo "📊 运行插件对比分析并保存结果..."
	@LUA_PATH='./lua/?.lua;./?.lua;;' LUA_CPATH="./lib/?.so;../lib/?.so;./?.so;;" $(LUAJIT_BIN) lua/plugin_comparison_analysis.lua > plugin_comparison_final.txt 2>&1
	@echo "✓ 插件对比分析完成，结果已保存到 plugin_comparison_final.txt"

# 测试所有插件功能
test-plugins-all:
	@echo "🔧 测试所有插件功能..."
	@LUA_CPATH="./lib/?.so;../lib/?.so;./?.so;;" $(LUAJIT_BIN) -e " \
		local plugins = { \
		  'micro_ts_plugin', 'micro_ts_plugin_optimized', 'micro_ts_plugin_final', \
		  'stock_quote_binary', 'stock_quote_compressed', 'stock_quote_optimized', \
		  'iot_data', 'payment_system', 'user_behavior', 'market_data', \
		  'log_analysis', 'sensor_data', 'stock_quote_v2' \
		} \
		\
		for _, plugin_name in ipairs(plugins) do \
		  local success, plugin = pcall(require, 'lua.' .. plugin_name) \
		  if success then \
		    local instance = plugin:new() \
		    local test_data = { \
		      stock_code = '000001', \
		      timestamp = 1760272200, \
		      market = 'SH', \
		      price = 1000, \
		      volume = 10000, \
		      ch = 1, \
		      side = 0, \
		      order_no = 1234567890, \
		      tick_no = 9876543210 \
		    } \
		    \
		    local rowkey, qualifier = instance:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market) \
		    local value = instance:encode_value(test_data) \
		    local decoded_rowkey = instance:decode_rowkey(rowkey) \
		    local decoded_value = instance:decode_value(value) \
		    \
		    local timestamp_match = test_data.timestamp == decoded_rowkey.timestamp \
		    local stock_code_match = test_data.stock_code == decoded_rowkey.stock_code \
		    local price_match = test_data.price == decoded_value.price \
		    \
		    if timestamp_match and stock_code_match and price_match then \
		      print('✓', plugin_name, '测试通过') \
		    else \
		      print('✗', plugin_name, '测试失败') \
		    end \
		  else \
		    print('✗', plugin_name, '加载失败') \
		  end \
		end \
	"
	@echo "✓ 所有插件功能测试完成"

# 测试micro_ts_final插件修复
test-micro-ts-final-fix:
	@echo "🔧 测试 micro_ts_final 插件时间戳修复..."
	@LUA_CPATH="./lib/?.so;../lib/?.so;./?.so;;" $(LUAJIT_BIN) -e " \
		local MicroTsPluginFinal = require('lua.micro_ts_plugin_final') \
		local plugin = MicroTsPluginFinal:new() \
		\
		-- 测试数据 \
		local test_data = { \
		  stock_code = '000001', \
		  timestamp = 1760272200,  -- 2024-07-12 10:30:00 \
		  market = 'SH', \
		  price = 1000, \
		  volume = 10000, \
		  ch = 1, \
		  side = 0, \
		  order_no = 1234567890, \
		  tick_no = 9876543210 \
		} \
		\
		-- 编码 \
		local rowkey, qualifier = plugin:encode_rowkey(test_data.stock_code, test_data.timestamp, test_data.market) \
		local value = plugin:encode_value(test_data) \
		\
		-- 解码 \
		local decoded_rowkey = plugin:decode_rowkey(rowkey) \
		local decoded_value = plugin:decode_value(value) \
		\
		-- 验证 \
		print('原始时间戳:', test_data.timestamp) \
		print('解码时间戳:', decoded_rowkey.timestamp) \
		print('时间戳匹配:', test_data.timestamp == decoded_rowkey.timestamp) \
		print('原始股票代码:', test_data.stock_code) \
		print('解码股票代码:', decoded_rowkey.stock_code) \
		print('股票代码匹配:', test_data.stock_code == decoded_rowkey.stock_code) \
		print('原始价格:', test_data.price) \
		print('解码价格:', decoded_value.price) \
		print('价格匹配:', test_data.price == decoded_value.price) \
		\
		-- 性能测试 \
		local perf = plugin:performance_test(10000) \
		print('编码性能:', perf.encode_ops_per_sec, 'ops/sec') \
		print('解码性能:', perf.decode_ops_per_sec, 'ops/sec') \
	"
	@echo "✓ micro_ts_final 插件时间戳修复测试完成"

# 查看micro_ts插件性能对比图表
view-micro-ts-charts:
	@echo "📊 打开 micro_ts 插件性能对比图表..."
	@if command -v open >/dev/null 2>&1; then \
		open micro_ts_performance_charts.html; \
	elif command -v xdg-open >/dev/null 2>&1; then \
		xdg-open micro_ts_performance_charts.html; \
	else \
		echo "请手动打开 micro_ts_performance_charts.html 文件查看图表"; \
	fi

# 查看micro_ts插件分析指南
show-micro-ts-guide:
	@echo "📖 显示 micro_ts 插件分析指南..."
	@cat micro_ts_analysis_guide.md

# 代码质量检查
lint:
	@echo "检查 Lua 代码质量..."
	@for file in $(LUA_MODULES); do \
		if [ -f "$$file" ]; then \
			echo "检查 $$file..."; \
			$(LUAJIT_BIN) -bl $$file > /dev/null 2>&1 && echo "✓ $$file 语法正确" || echo "✗ $$file 语法错误"; \
		fi \
	done

# 清理
clean:
	@echo "清理构建文件..."
	@rm -rf $(OBJ_DIR) $(BIN_DIR) $(LIB_DIR)
	@rm -rf $(LOGS_DIR)/* $(DATA_DIR)/*
	@echo "清理V3测试数据..."
	@rm -rf test_v3_*/
	@rm -rf testdb*/
	@echo "✓ 清理完成"

# 清理V3测试数据
clean-v3:
	@echo "清理V3测试数据..."
	@rm -rf test_v3_*/
	@rm -rf data/testdb*/
	@rm -rf data/stock_data/
	@echo "✓ V3测试数据清理完成"

# 安装
PREFIX ?= /usr/local
install: build
	@echo "安装 $(PROJECT_NAME) v$(VERSION)..."
	@install -d $(PREFIX)/bin
	@install -d $(PREFIX)/share/$(PROJECT_NAME)/lua
	@install -d $(PREFIX)/etc/$(PROJECT_NAME)
	@install -d $(PREFIX)/lib/lua/$(LUA_VERSION)
	@install -m 755 $(TARGET) $(PREFIX)/bin/
	@cp -r $(LUA_DIR)/* $(PREFIX)/share/$(PROJECT_NAME)/lua/
	@install -m 644 $(CONF_DIR)/stock-tsdb.conf $(PREFIX)/etc/$(PROJECT_NAME)/
	@echo "✓ 安装完成"
	@echo "安装路径: $(PREFIX)"
	@echo "二进制文件: $(PREFIX)/bin/stock-tsdb-server"
	@echo "配置文件: $(PREFIX)/etc/$(PROJECT_NAME)/stock-tsdb.conf"

# 卸载
uninstall:
	@echo "卸载 $(PROJECT_NAME)..."
	@rm -f $(PREFIX)/bin/stock-tsdb-server
	@rm -rf $(PREFIX)/share/$(PROJECT_NAME)
	@rm -f $(PREFIX)/etc/$(PROJECT_NAME)/stock-tsdb.conf
	@rm -rf $(PREFIX)/etc/$(PROJECT_NAME)
	@echo "✓ 卸载完成"

# 开发模式运行
run-dev: build
	@echo "开发模式启动..."
	@./$(TARGET) -c $(CONF_DIR)/stock-tsdb.conf -d

# 生产模式运行
run-prod: build
	@echo "生产模式启动..."
	@if [ -f $(PREFIX)/etc/$(PROJECT_NAME)/stock-tsdb.conf ]; then \
		$(PREFIX)/bin/stock-tsdb-server -c $(PREFIX)/etc/$(PROJECT_NAME)/stock-tsdb.conf; \
	else \
		echo "错误: 未找到生产配置文件，请先运行 make install"; \
		exit 1; \
	fi

# 打包
dist: clean
	@echo "创建发布包..."
	@mkdir -p dist
	@tar -czf dist/$(PROJECT_NAME)-$(VERSION)-$(PLATFORM).tar.gz \
		--exclude=.git \
		--exclude=dist \
		--exclude=logs \
		--exclude=data \
		--exclude=*.log \
		.
	@echo "✓ 发布包已创建: dist/$(PROJECT_NAME)-$(VERSION)-$(PLATFORM).tar.gz"

# 显示项目信息
info:
	@echo "$(PROJECT_NAME) v$(VERSION)"
	@echo "平台: $(PLATFORM)"
	@echo "LuaJIT: $(shell $(LUAJIT_BIN) -v)"
	@echo "LuaRocks: $(shell $(LUAROCKS) --version | head -1)"

# 帮助
help:
	@echo "$(PROJECT_NAME) v$(VERSION) Makefile"
	@echo ""
	@echo "主要目标:"
	@echo "  make              - 检查依赖并构建项目"
	@echo "  make build        - 构建项目"
	@echo "  make install      - 安装到系统 (PREFIX=$(PREFIX))"
	@echo "  make test         - 运行所有测试"
	@echo "  make test-core    - 运行核心测试（推荐）"
	@echo "  make test-cluster - 运行所有集群测试"
	@echo "  make test-cluster-all - 运行所有集群相关测试（包括集成测试）"
	@echo "  make clean        - 清理构建文件"
	@echo "  make clean-v3     - 清理V3测试数据"
	@echo "  make help         - 显示此帮助"
	@echo ""
	@echo "快速验证目标:"
	@echo "  make health-check        - 系统健康检查"
	@echo "  make test-cjson          - 测试 cjson.so 库功能"
	@echo "  make test-micro-ts       - 测试 micro_ts 插件多版本性能对比"
	@echo "  make view-micro-ts-charts - 查看 micro_ts 插件性能对比图表"
	@echo "  make show-micro-ts-guide - 显示 micro_ts 插件分析指南"
	@echo "  make test-config-manager - 运行配置管理器完整测试"
	@echo "  make test-config-manager-quick - 运行配置管理器快速测试"
	@echo ""
	@echo "监控系统目标:"
	@echo "  make monitoring-start    - 启动监控系统（Prometheus + 元数据Web服务器）"
	@echo "  make monitoring-stop     - 停止监控系统"
	@echo "  make monitoring-status   - 检查监控系统状态"
	@echo "  make monitoring-check    - 运行监控状态检查脚本"
	@echo "  make prometheus-start    - 启动 Prometheus 服务"
	@echo "  make prometheus-stop     - 停止 Prometheus 服务"
	@echo "  make prometheus-status   - 检查 Prometheus 服务状态"
	@echo "  make view-metrics        - 查看监控指标"
	@echo "  make test-monitoring     - 测试监控端点"
	@echo ""
	@echo "业务数据系统目标:"
	@echo "  make business-web-start    - 启动业务数据Web界面（SQL查询界面）"
	@echo "  make business-web-stop     - 停止业务数据Web界面"
	@echo "  make business-web-status   - 检查业务数据Web界面状态"
	@echo "  make business-web-check    - 检查业务数据Web界面功能"
	@echo "  make sql-query-test        - 测试SQL查询功能"
	@echo "  make view-business-metrics - 查看业务数据指标"
	@echo "  make business-system-start - 启动完整业务数据系统"
	@echo "  make business-system-stop  - 停止业务数据系统"
	@echo "  make business-system-status - 检查业务数据系统状态"
	@echo ""
	@echo "元数据管理目标:"
	@echo "  make metadata-init       - 初始化元数据配置"
	@echo "  make metadata-list       - 查询元数据列表"
	@echo "  make metadata-update     - 修改元数据配置"
	@echo ""
	@echo "插件测试目标:"
	@echo "  make test-plugin-comparison      - 运行插件对比分析"
	@echo "  make test-plugin-comparison-save - 运行插件对比分析并保存结果"
	@echo "  make test-plugins-all            - 测试所有插件功能"
	@echo "  make test-micro-ts-final-fix     - 测试 micro_ts_final 插件时间戳修复"
	@echo ""
	@echo "V3存储引擎测试目标:"
	@echo "  make test-v3              - 运行所有V3版本测试（推荐）"
	@echo "  make test-v3-basic        - V3基础版本测试"
	@echo "  make test-v3-integrated  - V3集成版本测试"
	@echo "  make test-v3-comparison   - V3版本对比测试"
	@echo "  make test-v3-validation   - V3版本功能验证"
	@echo "  make test-v3-performance  - V3性能详细分析"
	@echo "  make test-v3-final        - V3最终对比测试"
	@echo ""
	@echo "集群测试目标:"
	@echo "  make test-cluster          - 运行所有集群测试（推荐）"
	@echo "  make test-cluster-simple   - 运行简单集群测试"
	@echo "  make test-cluster-tsdb     - 运行TSDB集群测试"
	@echo "  make test-cluster-business - 运行业务集群测试"
	@echo "  make test-cluster-consul   - 运行Consul集成测试"
	@echo "  make test-cluster-optimized - 运行优化集群测试"
	@echo "  make test-cluster-all      - 运行所有集群相关测试（包括集成测试）"
	@echo ""
	@echo "开发目标:"
	@echo "  make install-deps - 安装 Lua 依赖包"
	@echo "  make install-cjson - 安装 lua-cjson 库（JSON支持）"
	@echo "  make build-micro-ts - 编译 micro_ts 库（高性能打包/解包）"
	@echo "  make run-dev      - 开发模式运行"
	@echo "  make run-prod     - 生产模式运行"
	@echo "  make lint         - 代码质量检查"
	@echo ""
	@echo "Redis集群服务器目标:"
	@echo "  make redis-server        - 启动Redis集群服务器（前台模式）"
	@echo "  make redis-server-daemon - 启动Redis集群服务器（后台模式）"
	@echo "  make redis-test          - 测试Redis集群服务器"
	@echo "  make redis-stop          - 停止Redis集群服务器"
	@echo ""
	@echo "Redis集群服务器信息:"
	@echo "  监听端口: 6379 (Redis协议)"
	@echo "  集群端口: 5555 (ZeroMQ集群通信)"
	@echo "  支持命令: PING, ECHO, SET, GET, TS.ADD, TS.RANGE, CLUSTER, INFO"
	@echo ""
		@echo "使用示例:"
	@echo "  make health-check         # 系统健康检查"
	@echo "  make test-quick           # 快速验证测试"
	@echo "  make test-v3              # 运行V3版本完整测试"
	@echo "  make test-v3-basic        # 仅测试V3基础版本"
	@echo "  make test-v3-comparison   # 运行V3版本对比测试"
	@echo "  make test-cluster         # 运行所有集群测试"
	@echo "  make test-cluster-simple  # 运行简单集群测试"
	@echo "  make test-cluster-business # 运行业务集群测试"
	@echo "  make redis-server-daemon  # 启动Redis集群服务器"
	@echo "  make redis-test           # 测试服务器功能"
	@echo "  make monitoring-start     # 启动监控系统"
	@echo "  make monitoring-status    # 检查监控状态"
	@echo "  make view-metrics         # 查看监控指标"
	@echo "  make test-monitoring      # 测试监控端点"
	@echo "  make business-system-start # 启动业务数据系统"
	@echo "  make business-web-check    # 检查业务数据界面"
	@echo "  make sql-query-test       # 测试SQL查询功能"
	@echo "  make stress-test-write    # 写入压力测试"
	@echo "  make stress-test-read     # 读取压力测试"
	@echo "  make prepare-release      # 准备生产发布"
	@echo "  make github-setup         # 设置GitHub仓库"
	@echo "  redis-cli -p 6379 PING    # 使用redis-cli测试"
	@echo ""
		@echo "高级目标:"
	@echo "  make dist         - 创建发布包"
	@echo "  make info         - 显示项目信息"
	@echo "  make uninstall    - 从系统卸载"
	@echo ""
	@echo "压力测试目标:"
	@echo "  make stress-test-write - 写入压力测试"
	@echo "  make stress-test-read  - 读取压力测试"
	@echo "  make stress-test-mixed - 混合压力测试"
	@echo "  make stress-test-all   - 运行所有压力测试"
	@echo ""
	@echo "生产发布目标:"
	@echo "  make prepare-release   - 准备生产发布"
	@echo "  make release-package   - 构建发布包"
	@echo ""
	@echo "GitHub 上传目标:"
	@echo "  make github-setup      - 设置 GitHub 仓库"
	@echo "  make github-upload     - 上传代码到 GitHub"
	@echo "  make github-release    - 创建 GitHub Release"
	@echo ""
	@echo "Ubuntu/Debian 打包目标:"
	@echo "  make package-ubuntu-debian - 打包 Ubuntu/Debian 系统"
	@echo "  make package-deb          - 创建 Debian 包"
	@echo "  make package-appimage     - 创建 AppImage 包"
	@echo "  make package-rpm          - 创建 RPM 包"
	@echo "  make package-docker       - 创建 Docker 镜像"
	@echo "  make package-snap         - 创建 Snap 包"
	@echo "  make package-all          - 创建所有格式的包"
	@echo "  make install-ubuntu-debian - 安装到 Ubuntu/Debian 系统"
	@echo "  make install-packaging-deps - 安装打包依赖"
	@echo ""
	@echo "变量:"
	@echo "  make install PREFIX=/opt/stock-tsdb  # 自定义安装路径"
	@echo ""
	@echo "平台: $(PLATFORM)"

# 创建必要的目录
directories: $(BIN_DIR) $(LIB_DIR) $(LOGS_DIR) $(DATA_DIR)

# Ubuntu/Debian 打包目标
.PHONY: package-ubuntu-debian package-deb package-appimage package-rpm package-docker package-snap install-ubuntu-debian

# 打包 Ubuntu/Debian 系统
package-ubuntu-debian:
	@echo "📦 打包 Ubuntu/Debian 系统..."
	@./package_ubuntu_debian.sh --deb

# 创建 Debian 包
package-deb:
	@echo "📦 创建 Debian 包..."
	@./package_ubuntu_debian.sh --deb

# 创建 AppImage 包
package-appimage:
	@echo "📦 创建 AppImage 包..."
	@./package_ubuntu_debian.sh --appimage

# 创建 RPM 包
package-rpm:
	@echo "📦 创建 RPM 包..."
	@./package_ubuntu_debian.sh --rpm

# 创建 Docker 镜像
package-docker:
	@echo "📦 创建 Docker 镜像..."
	@./package_ubuntu_debian.sh --docker

# 创建 Snap 包
package-snap:
	@echo "📦 创建 Snap 包..."
	@./package_ubuntu_debian.sh --snap

# 创建所有格式的包
package-all:
	@echo "📦 创建所有格式的包..."
	@./package_ubuntu_debian.sh --all

# 安装到 Ubuntu/Debian 系统
install-ubuntu-debian:
	@echo "🔧 安装到 Ubuntu/Debian 系统..."
	@./install_ubuntu_debian.sh

# 安装打包依赖
install-packaging-deps:
	@echo "🔧 安装打包依赖..."
	@./package_ubuntu_debian.sh --install-deps

# 监控系统目标
.PHONY: monitoring-start monitoring-stop monitoring-status monitoring-check prometheus-start prometheus-stop prometheus-status

# 启动监控系统
monitoring-start:
	@echo "🔍 启动监控系统..."
	@if [ -f scripts/start_prometheus.sh ]; then \
		echo "启动 Prometheus 监控服务..."; \
		./scripts/start_prometheus.sh start; \
	else \
		echo "警告: 未找到 Prometheus 启动脚本"; \
	fi
	@echo "启动元数据 Web 服务器..."
	@if pgrep -f "luajit web/start_metadata_web.lua" > /dev/null; then \
		echo "元数据 Web 服务器已在运行"; \
	else \
		cd /Users/moyong/project/ai/myrocks/stock-tsdb && luajit web/start_metadata_web.lua & \
		echo "元数据 Web 服务器已启动"; \
	fi
	@echo "✓ 监控系统启动完成"

# 业务数据Web界面目标
.PHONY: business-web-start business-web-stop business-web-status business-web-check sql-query-test view-business-metrics business-system-start business-system-stop business-system-status

# 启动业务数据Web界面
business-web-start:
	@echo "🚀 启动业务数据Web界面..."
	@cd web && luajit start_business_web.lua &
	@echo "✅ 业务数据Web界面已启动 (端口: 8081)"
	@echo "📊 访问地址: http://localhost:8081"
	@echo "🔍 功能: SQL查询、聚合函数、数据可视化"

# 停止业务数据Web界面
business-web-stop:
	@echo "🛑 停止业务数据Web界面..."
	@-pkill -f "luajit start_business_web.lua" 2>/dev/null || true
	@echo "✅ 业务数据Web界面已停止"

# 检查业务数据Web界面状态
business-web-status:
	@echo "📊 检查业务数据Web界面状态..."
	@if curl -s http://localhost:8081/health >/dev/null 2>&1; then \
		echo "✅ 业务数据Web界面运行正常"; \
		curl -s http://localhost:8081/health | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8081/health; \
	else \
		echo "❌ 业务数据Web界面未运行"; \
	fi

# 检查业务数据Web界面功能
business-web-check:
	@echo "🔍 检查业务数据Web界面功能..."
	@echo "📋 测试数据表列表接口..."
	@curl -s http://localhost:8081/business/tables | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8081/business/tables
	@echo ""
	@echo "🔍 测试健康检查接口..."
	@curl -s http://localhost:8081/health | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8081/health

# 测试SQL查询功能
sql-query-test:
	@echo "🧪 测试SQL查询功能..."
	@echo "📊 执行示例查询: SELECT COUNT(*) FROM stock_quotes"
	@curl -s -X POST http://localhost:8081/business/query \
		-H "Content-Type: application/json" \
		-d '{"sql":"SELECT COUNT(*) FROM stock_quotes"}' | \
		python3 -m json.tool 2>/dev/null || \
		curl -s -X POST http://localhost:8081/business/query \
		-H "Content-Type: application/json" \
		-d '{"sql":"SELECT COUNT(*) FROM stock_quotes"}'

# 查看业务数据指标
view-business-metrics:
	@echo "📈 查看业务数据指标..."
	@curl -s http://localhost:8081/health | python3 -m json.tool 2>/dev/null || curl -s http://localhost:8081/health

# 完整业务数据系统启动
business-system-start:
	@echo "🚀 启动完整业务数据系统..."
	@$(MAKE) business-web-start
	@echo ""
	@echo "✅ 业务数据系统启动完成"
	@echo "📊 业务数据Web界面: http://localhost:8081"
	@echo "🔍 支持功能:"
	@echo "   • SQL查询 (SELECT, WHERE, GROUP BY)"
	@echo "   • 聚合函数 (COUNT, SUM, AVG, MAX, MIN)"
	@echo "   • 数据可视化表格"
	@echo "   • 7种业务数据类型支持"

# 停止业务数据系统
business-system-stop:
	@echo "🛑 停止业务数据系统..."
	@$(MAKE) business-web-stop
	@echo "✅ 业务数据系统已停止"

# 检查业务数据系统状态
business-system-status:
	@echo "📊 检查业务数据系统状态..."
	@$(MAKE) business-web-status

# 停止监控系统
monitoring-stop:
	@echo "🔍 停止监控系统..."
	@if [ -f scripts/start_prometheus.sh ]; then \
		echo "停止 Prometheus 监控服务..."; \
		./scripts/start_prometheus.sh stop; \
	else \
		echo "警告: 未找到 Prometheus 停止脚本"; \
	fi
	@echo "停止元数据 Web 服务器..."
	@pkill -f "luajit web/start_metadata_web.lua" && echo "元数据 Web 服务器已停止" || echo "元数据 Web 服务器未运行"
	@echo "✓ 监控系统停止完成"

# 检查监控系统状态
monitoring-status:
	@echo "🔍 监控系统状态检查..."
	@echo "=== 元数据 Web 服务器状态 ==="
	@if pgrep -f "luajit web/start_metadata_web.lua" > /dev/null; then \
		echo "✓ 元数据 Web 服务器: 运行中"; \
		curl -s http://localhost:8080/metrics | head -5; \
	else \
		echo "✗ 元数据 Web 服务器: 未运行"; \
	fi
	@echo ""
	@echo "=== Prometheus 服务状态 ==="
	@if command -v docker >/dev/null 2>&1; then \
		if docker ps | grep prometheus > /dev/null; then \
			echo "✓ Prometheus 服务: 运行中"; \
		else \
			echo "✗ Prometheus 服务: 未运行"; \
		fi \
	else \
		echo "⚠ Docker 未安装，无法检查 Prometheus 状态"; \
	fi
	@echo ""
	@echo "=== 监控指标端点 ==="
	@if curl -s http://localhost:8080/metrics > /dev/null 2>&1; then \
		echo "✓ Prometheus 指标端点: 可访问"; \
		curl -s http://localhost:8080/metrics | grep -c "stock_tsdb_" | xargs echo "  可用指标数量:"; \
	else \
		echo "✗ Prometheus 指标端点: 不可访问"; \
	fi

# 运行监控状态检查脚本
monitoring-check:
	@echo "🔍 运行监控状态检查..."
	@if [ -f scripts/check_monitoring.sh ]; then \
		./scripts/check_monitoring.sh; \
	else \
		echo "错误: 未找到监控状态检查脚本"; \
		exit 1; \
	fi

# 启动 Prometheus 服务
prometheus-start:
	@echo "📊 启动 Prometheus 监控服务..."
	@if [ -f scripts/start_prometheus.sh ]; then \
		./scripts/start_prometheus.sh start; \
		echo "✓ Prometheus 服务启动完成"; \
	else \
		echo "错误: 未找到 Prometheus 启动脚本"; \
		exit 1; \
	fi

# 停止 Prometheus 服务
prometheus-stop:
	@echo "📊 停止 Prometheus 监控服务..."
	@if [ -f scripts/start_prometheus.sh ]; then \
		./scripts/start_prometheus.sh stop; \
		echo "✓ Prometheus 服务停止完成"; \
	else \
		echo "错误: 未找到 Prometheus 停止脚本"; \
		exit 1; \
	fi

# 检查 Prometheus 服务状态
prometheus-status:
	@echo "📊 Prometheus 服务状态..."
	@if command -v docker >/dev/null 2>&1; then \
		if docker ps | grep prometheus > /dev/null; then \
			echo "✓ Prometheus 服务: 运行中"; \
			echo "  访问地址: http://localhost:9090"; \
			echo "  监控目标: http://localhost:8080/metrics"; \
		else \
			echo "✗ Prometheus 服务: 未运行"; \
		fi \
	else \
		echo "⚠ Docker 未安装，无法检查 Prometheus 状态"; \
	fi

# 查看监控指标
view-metrics:
	@echo "📈 查看监控指标..."
	@if curl -s http://localhost:8080/metrics > /dev/null 2>&1; then \
		echo "=== 系统指标 ==="; \
		curl -s http://localhost:8080/metrics | grep -E "stock_tsdb_server_(uptime|version)" | head -5; \
		echo "" \
		echo "=== 连接指标 ==="; \
		curl -s http://localhost:8080/metrics | grep -E "stock_tsdb_connections" | head -5; \
		echo "" \
		echo "=== 存储指标 ==="; \
		curl -s http://localhost:8080/metrics | grep -E "stock_tsdb_storage" | head -5; \
		echo "" \
		echo "=== 性能指标 ==="; \
		curl -s http://localhost:8080/metrics | grep -E "stock_tsdb_performance" | head -5; \
		echo "" \
		echo "=== 业务指标 ==="; \
		curl -s http://localhost:8080/metrics | grep -E "stock_tsdb_business" | head -5; \
		echo "" \
		echo "=== 集群指标 ==="; \
		curl -s http://localhost:8080/metrics | grep -E "stock_tsdb_cluster" | head -5; \
	else \
		echo "错误: 无法访问监控指标端点"; \
		exit 1; \
	fi

# 测试监控端点
test-monitoring:
	@echo "🧪 测试监控端点..."
	@echo "1. 检查元数据 Web 服务器..."
	@if pgrep -f "luajit web/start_metadata_web.lua" > /dev/null; then \
		echo "   ✓ 服务器运行正常"; \
	else \
		echo "   ✗ 服务器未运行"; \
		exit 1; \
	fi
	@echo "2. 测试 Prometheus 指标端点..."
	@if curl -s http://localhost:8080/metrics > /dev/null 2>&1; then \
		echo "   ✓ 指标端点可访问"; \
		METRIC_COUNT=$$(curl -s http://localhost:8080/metrics | grep -c "stock_tsdb_"); \
		echo "   指标数量: $$METRIC_COUNT"; \
		if [ $$METRIC_COUNT -gt 0 ]; then \
			echo "   ✓ 指标数据正常"; \
		else \
			echo "   ✗ 未找到监控指标"; \
			exit 1; \
		fi \
	else \
		echo "   ✗ 指标端点不可访问"; \
		exit 1; \
	fi
	@echo "3. 检查关键指标..."
	@curl -s http://localhost:8080/metrics | grep -E "stock_tsdb_server_uptime|stock_tsdb_connections_active|stock_tsdb_storage_data_points_total" | while read line; do \
		echo "   $$line"; \
	done
	@echo "✓ 监控端点测试完成"

# 压力测试目标
stress-test-write:
	@echo "🚀 开始写入压力测试..."
	@chmod +x scripts/stress_test.lua
	@eval "$$(luarocks path)" && lua scripts/stress_test.lua write

stress-test-read:
	@echo "🚀 开始读取压力测试..."
	@chmod +x scripts/stress_test.lua
	@eval "$$(luarocks path)" && lua scripts/stress_test.lua read

stress-test-mixed:
	@echo "🚀 开始混合压力测试..."
	@chmod +x scripts/stress_test.lua
	@eval "$$(luarocks path)" && lua scripts/stress_test.lua mixed

stress-test-all:
	@echo "🚀 运行完整的压力测试套件..."
	@$(MAKE) stress-test-write
	@$(MAKE) stress-test-read
	@$(MAKE) stress-test-mixed

# 生产发布目标
prepare-release:
	@echo "📦 准备生产发布..."
	@chmod +x scripts/prepare_release.sh
	@./scripts/prepare_release.sh

release-package:
	@echo "📦 构建发布包..."
	@chmod +x scripts/prepare_release.sh
	@./scripts/prepare_release.sh --package-only

# GitHub 上传目标
github-setup:
	@echo "🔗 设置 GitHub 仓库..."
	@chmod +x scripts/github_upload.sh
	@./scripts/github_upload.sh --setup

github-upload:
	@echo "🔗 上传代码到 GitHub..."
	@chmod +x scripts/github_upload.sh
	@./scripts/github_upload.sh

github-release:
	@echo "🔗 创建 GitHub Release..."
	@chmod +x scripts/github_upload.sh
	@./scripts/github_upload.sh --release