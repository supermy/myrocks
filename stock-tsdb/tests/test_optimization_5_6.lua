#!/usr/bin/env luajit
-- 优化方案5和6的测试

package.path = package.path .. ";./?.lua;./lua/?.lua"

local ConfigManagerAdvanced = require("lua.config_manager_advanced")
local SecurityManager = require("lua.security_manager")
local DeploymentManager = require("lua.deployment_manager")
local PerformanceBenchmark = require("lua.performance_benchmark")

print("=== 优化方案5和6测试 ===")
print("测试时间: " .. os.date("%Y-%m-%d %H:%M:%S"))
print("")

local test_results = {
    passed = 0,
    failed = 0
}

local function assert_true(condition, message)
    if condition then
        print("✓ " .. message)
        test_results.passed = test_results.passed + 1
        return true
    else
        print("✗ " .. message)
        test_results.failed = test_results.failed + 1
        return false
    end
end

-- ==================== 测试优化方案5: 高级配置管理 ====================
print("--- 测试优化方案5: 高级配置管理 ---")

local config_mgr = ConfigManagerAdvanced:new({
    auto_save = false,
    max_history = 10
})

-- 测试设置配置
local set_result = config_mgr:set("database.host", "localhost")
assert_true(set_result == true, "成功设置配置项")

config_mgr:set("database.port", 3306)
config_mgr:set("database.name", "stock_tsdb")

-- 测试获取配置
local host = config_mgr:get("database.host")
assert_true(host == "localhost", "成功获取配置项")

local port = config_mgr:get("database.port")
assert_true(port == 3306, "获取数字配置项正确")

-- 测试默认值
local timeout = config_mgr:get("database.timeout", 30)
assert_true(timeout == 30, "获取默认值正确")

-- 测试批量设置
local batch_updates = {
    ["cache.enabled"] = true,
    ["cache.size"] = 1000,
    ["cache.ttl"] = 3600
}
local batch_count = config_mgr:set_batch(batch_updates, {skip_save = true})
assert_true(batch_count == 3, "批量设置配置成功")

-- 测试配置验证器
config_mgr:register_validator("database.port", function(value)
    if type(value) ~= "number" then
        return false, "端口必须是数字"
    end
    if value < 1 or value > 65535 then
        return false, "端口范围无效"
    end
    return true
end)

local valid_result = config_mgr:validate("database.port", 3306)
assert_true(valid_result == true, "配置验证通过")

-- 测试配置历史
local history = config_mgr:get_history("database.host", 5)
assert_true(#history >= 1, "配置历史记录存在")

-- 获取统计信息
local config_stats = config_mgr:get_stats()
assert_true(config_stats.stats.total_updates >= 4, "配置统计正确")

print("")

-- ==================== 测试优化方案5: 安全管理 ====================
print("--- 测试优化方案5: 安全管理 ---")

local security = SecurityManager:new({
    enabled = true,
    token_expiry = 3600,
    max_login_attempts = 3
})

-- 测试用户注册
local reg_result = security:register_user("testuser", "Password123", "USER", {email = "test@example.com"})
assert_true(reg_result == true, "用户注册成功")

-- 测试密码强度验证
local weak_reg = security:register_user("testuser2", "weak", "USER")
assert_true(weak_reg == false, "弱密码注册被拒绝")

-- 测试用户登录
local login_result, token, session = security:login("testuser", "Password123", {ip = "127.0.0.1"})
assert_true(login_result == true, "用户登录成功")
assert_true(token ~= nil, "登录返回令牌")

-- 测试令牌验证
local valid_token, session_info = security:validate_token(token)
assert_true(valid_token == true, "令牌验证通过")
assert_true(session_info.username == "testuser", "会话信息正确")

-- 测试权限检查
local perm_result = security:check_permission(token, "read")
assert_true(perm_result == true, "权限检查通过")

-- 测试API密钥生成
local api_key = security:generate_api_key("testuser", {"read", "write"}, 30)
assert_true(api_key ~= nil and api_key ~= "disabled", "API密钥生成成功")

-- 验证API密钥
local valid_api, api_info = security:validate_api_key(api_key)
assert_true(valid_api == true, "API密钥验证通过")

-- 测试加密解密
local original_data = "sensitive data"
local encrypted = security:encrypt(original_data, "my_key")
local decrypted = security:decrypt(encrypted, "my_key")
assert_true(decrypted == original_data, "加密解密正确")

-- 获取审计日志
local audit_logs = security:get_audit_logs({limit = 10})
assert_true(#audit_logs >= 1, "审计日志存在")

-- 获取安全统计
local security_stats = security:get_stats()
assert_true(security_stats.total_users >= 1, "安全统计正确")

print("")

-- ==================== 测试优化方案6: 部署管理 ====================
print("--- 测试优化方案6: 部署管理 ---")

local deploy_mgr = DeploymentManager:new({
    environment = "testing",
    version = "1.0.0",
    work_dir = "/tmp/test-deploy"
})

-- 测试Docker配置生成
local docker_configs = deploy_mgr:generate_docker_config({replicas = 3})
assert_true(docker_configs.dockerfile ~= nil, "Dockerfile生成成功")
assert_true(docker_configs.docker_compose ~= nil, "Docker Compose配置生成成功")
assert_true(docker_configs.kubernetes ~= nil, "Kubernetes配置生成成功")

-- 测试健康检查
local health = deploy_mgr:health_check()
assert_true(health ~= nil, "健康检查执行成功")
assert_true(health.overall_status ~= nil, "健康状态获取成功")
assert_true(health.checks ~= nil, "检查项存在")

-- 获取部署统计
local deploy_stats = deploy_mgr:get_stats()
assert_true(deploy_stats.environment == "testing", "部署环境正确")
assert_true(deploy_stats.version == "1.0.0", "部署版本正确")

print("")

-- ==================== 测试优化方案6: 性能基准 ====================
print("--- 测试优化方案6: 性能基准 ---")

local benchmark = PerformanceBenchmark:new({
    test_duration = 1,  -- 1秒用于测试
    warmup_duration = 0,
    concurrency = 5
})

-- 测试单个场景
local scenario = {
    name = "测试场景",
    type = "write",
    concurrent = 1,
    batch_size = 10,
    duration = 1
}

local result = benchmark:run_scenario(scenario, nil)
assert_true(result ~= nil, "基准测试场景执行成功")
assert_true(result.status == "completed", "测试场景完成")
assert_true(result.metrics ~= nil, "测试指标存在")

-- 测试报告生成
local report = benchmark:_generate_report({result})
assert_true(report ~= nil, "测试报告生成成功")
assert_true(report.summary ~= nil, "报告摘要存在")
assert_true(report.summary.total_scenarios == 1, "场景统计正确")

-- 测试HTML报告导出
local html_report = benchmark:_generate_html_report(report)
assert_true(html_report ~= nil, "HTML报告生成成功")
assert_true(string.find(html_report, "<html>") ~= nil, "HTML格式正确")

print("")

-- ==================== 测试结果汇总 ====================
print("=== 测试结果汇总 ===")
print(string.format("通过: %d", test_results.passed))
print(string.format("失败: %d", test_results.failed))
print(string.format("成功率: %.1f%%", (test_results.passed / (test_results.passed + test_results.failed)) * 100))

if test_results.failed == 0 then
    print("\n🎉 优化方案5和6测试全部通过！")
    print("\n已实现的优化功能:")
    print("  优化方案5:")
    print("    ✓ 高级配置管理（动态更新、版本控制）")
    print("    ✓ 配置验证器")
    print("    ✓ 配置历史与回滚")
    print("    ✓ 安全管理（认证、授权、加密）")
    print("    ✓ 审计日志")
    print("  优化方案6:")
    print("    ✓ 部署管理（自动化部署、容器化）")
    print("    ✓ 健康检查")
    print("    ✓ 性能基准测试工具")
    print("    ✓ 测试报告生成")
    os.exit(0)
else
    print("\n⚠ 部分测试失败")
    os.exit(1)
end
