-- 前缀压缩配置模块
-- 为不同ColumnFamily设置不同的前缀策略

local PrefixCompressionConfig = {}

-- 股票数据前缀策略配置
PrefixCompressionConfig.stock_prefix_strategies = {
    -- 按股票代码前缀长度配置
    ["default"] = {
        prefix_length = 6,  -- 默认6字节前缀（股票代码前3个字符）
        description = "默认股票前缀策略"
    },
    ["hot_stock"] = {
        prefix_length = 8,  -- 热门股票使用8字节前缀
        description = "热门股票前缀策略"
    },
    ["index_stock"] = {
        prefix_length = 4,  -- 指数股票使用4字节前缀
        description = "指数股票前缀策略"
    }
}

-- 时间序列数据前缀策略配置
PrefixCompressionConfig.timeseries_prefix_strategies = {
    ["default"] = {
        prefix_length = 8,  -- 默认8字节前缀（时间戳前8字节）
        description = "默认时间序列前缀策略"
    },
    ["high_frequency"] = {
        prefix_length = 12,  -- 高频数据使用12字节前缀
        description = "高频时间序列前缀策略"
    },
    ["low_frequency"] = {
        prefix_length = 4,  -- 低频数据使用4字节前缀
        description = "低频时间序列前缀策略"
    }
}

-- ColumnFamily前缀策略映射
PrefixCompressionConfig.cf_prefix_mapping = {
    -- 热数据CF前缀策略
    ["cf_"] = "hot_stock",  -- 热数据CF使用热门股票策略
    ["cold_"] = "default",  -- 冷数据CF使用默认策略
    ["default"] = "default"  -- 默认CF使用默认策略
}

-- 根据CF名称获取前缀策略
function PrefixCompressionConfig.get_prefix_strategy_for_cf(cf_name)
    if not cf_name then
        return PrefixCompressionConfig.stock_prefix_strategies["default"]
    end
    
    -- 根据CF名称前缀匹配策略
    for prefix, strategy_name in pairs(PrefixCompressionConfig.cf_prefix_mapping) do
        if cf_name:sub(1, #prefix) == prefix then
            return PrefixCompressionConfig.stock_prefix_strategies[strategy_name]
        end
    end
    
    -- 默认策略
    return PrefixCompressionConfig.stock_prefix_strategies["default"]
end

-- 根据CF名称和热数据状态获取前缀策略
function PrefixCompressionConfig.get_strategy_for_cf(cf_name, is_hot)
    if not cf_name then
        return {
            name = "default",
            prefix_length = 6,
            description = "默认前缀压缩策略"
        }
    end
    
    -- 根据CF名称前缀匹配策略
    for prefix, strategy_name in pairs(PrefixCompressionConfig.cf_prefix_mapping) do
        if cf_name:sub(1, #prefix) == prefix then
            local strategy = PrefixCompressionConfig.stock_prefix_strategies[strategy_name]
            if strategy then
                return {
                    name = strategy_name,
                    prefix_length = strategy.prefix_length,
                    description = strategy.description
                }
            end
        end
    end
    
    -- 默认策略
    return {
        name = "default",
        prefix_length = 6,
        description = "默认前缀压缩策略"
    }
end

-- 根据数据类型获取前缀策略
function PrefixCompressionConfig.get_prefix_strategy_for_data_type(data_type)
    if data_type == "stock" then
        return PrefixCompressionConfig.stock_prefix_strategies["default"]
    elseif data_type == "timeseries" then
        return PrefixCompressionConfig.timeseries_prefix_strategies["default"]
    else
        return PrefixCompressionConfig.stock_prefix_strategies["default"]
    end
end

-- 获取所有前缀策略配置
function PrefixCompressionConfig.get_all_strategies()
    local all_strategies = {}
    
    -- 合并股票和时间序列策略
    for name, strategy in pairs(PrefixCompressionConfig.stock_prefix_strategies) do
        all_strategies["stock_" .. name] = strategy
    end
    
    for name, strategy in pairs(PrefixCompressionConfig.timeseries_prefix_strategies) do
        all_strategies["timeseries_" .. name] = strategy
    end
    
    return all_strategies
end

-- 验证前缀长度是否合理
function PrefixCompressionConfig.validate_prefix_length(prefix_length, data_type)
    if prefix_length < 0 then
        return false, "前缀长度不能为负数"
    end
    
    if data_type == "stock" then
        if prefix_length > 20 then
            return false, "股票数据前缀长度不能超过20字节"
        end
    elseif data_type == "timeseries" then
        if prefix_length > 16 then
            return false, "时间序列数据前缀长度不能超过16字节"
        end
    end
    
    return true
end

-- 生成前缀压缩配置摘要
function PrefixCompressionConfig.generate_summary()
    local summary = {}
    
    summary.stock_strategies = {}
    for name, strategy in pairs(PrefixCompressionConfig.stock_prefix_strategies) do
        table.insert(summary.stock_strategies, {
            name = name,
            prefix_length = strategy.prefix_length,
            description = strategy.description
        })
    end
    
    summary.timeseries_strategies = {}
    for name, strategy in pairs(PrefixCompressionConfig.timeseries_prefix_strategies) do
        table.insert(summary.timeseries_strategies, {
            name = name,
            prefix_length = strategy.prefix_length,
            description = strategy.description
        })
    end
    
    summary.cf_mapping = {}
    for prefix, strategy in pairs(PrefixCompressionConfig.cf_prefix_mapping) do
        table.insert(summary.cf_mapping, {
            cf_prefix = prefix,
            strategy = strategy
        })
    end
    
    return summary
end

return PrefixCompressionConfig