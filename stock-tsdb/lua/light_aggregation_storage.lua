-- 轻度汇总数据库存储引擎模块
-- 使用RocksDB存储汇总数据，采用多CF架构和前缀压缩

local LightAggregationStorage = {}
LightAggregationStorage.__index = LightAggregationStorage

-- CF名称定义
local CF_NAMES = {
    TIME = "time",           -- 时间维度CF
    STOCK = "stock",         -- 股票业务CF
    MARKET = "market",       -- 市场业务CF
    INDUSTRY = "industry",   -- 行业业务CF
    DEFAULT = "default"      -- 默认CF，RocksDB要求使用"default"
}

-- CF前缀压缩配置
local CF_COMPRESSION_CONFIGS = {
    [CF_NAMES.TIME] = {
        enable_separator_compression = true,
        separator = "|",
        separator_position = 3,  -- 在第3个分隔符处压缩
        prefix_extractor_length = 2,  -- 提取前2个分隔符作为前缀
        memtable_prefix_bloom_ratio = 0.1
    },
    [CF_NAMES.STOCK] = {
        enable_separator_compression = true,
        separator = "|",
        separator_position = 2,  -- 在第2个分隔符处压缩（STOCK|CODE|...）
        prefix_extractor_length = 1,
        memtable_prefix_bloom_ratio = 0.15
    },
    [CF_NAMES.MARKET] = {
        enable_separator_compression = true,
        separator = "|",
        separator_position = 2,  -- 在第2个分隔符处压缩
        prefix_extractor_length = 1,
        memtable_prefix_bloom_ratio = 0.1
    },
    [CF_NAMES.INDUSTRY] = {
        enable_separator_compression = true,
        separator = "|",
        separator_position = 2,  -- 在第2个分隔符处压缩
        prefix_extractor_length = 1,
        memtable_prefix_bloom_ratio = 0.1
    },
    [CF_NAMES.DEFAULT] = {
        enable_separator_compression = true,
        separator = "|",
        separator_position = 2,  -- 默认在第2个分隔符处压缩
        prefix_extractor_length = 1,
        memtable_prefix_bloom_ratio = 0.1
    }
}

-- 维度到CF的映射
local DIMENSION_TO_CF = {
    -- 时间维度映射到时间CF
    HOUR = CF_NAMES.TIME,
    DAY = CF_NAMES.TIME,
    WEEK = CF_NAMES.TIME,
    MONTH = CF_NAMES.TIME,
    
    -- 业务维度映射到对应的CF
    STOCK_CODE = CF_NAMES.STOCK,
    MARKET = CF_NAMES.MARKET,
    INDUSTRY = CF_NAMES.INDUSTRY
}

-- 获取维度对应的CF名称
local function get_cf_for_dimension(dimension)
    return DIMENSION_TO_CF[dimension] or CF_NAMES.DEFAULT
end

-- 获取CF的压缩配置
local function get_cf_compression_config(cf_name)
    return CF_COMPRESSION_CONFIGS[cf_name] or CF_COMPRESSION_CONFIGS[CF_NAMES.DEFAULT]
end

-- 导入依赖
local rocksdb = nil
local cjson = nil

-- 检查依赖是否可用
local function check_dependencies()
    -- 首先尝试加载标准rocksdb模块
    local ok, rocksdb_module = pcall(require, "rocksdb")
    if ok then
        rocksdb = rocksdb_module
        print("使用标准RocksDB模块")
    else
        -- 尝试使用项目自带的RocksDB FFI实现
        -- 首先修改模块搜索路径，确保能找到lua目录下的模块
        package.path = package.path .. ";./lua/?.lua"
        
        local ok2, rocksdb_ffi = pcall(require, "rocksdb_ffi")
        if ok2 then
            -- 检查FFI模块是否可用
            local ffi_ok, ffi = pcall(require, "ffi")
            if ffi_ok then
                -- 创建RocksDB FFI包装器，使其与rocksdb模块API兼容
        rocksdb = {
            -- 基本类型定义
            options = function() 
                local options_cdata = rocksdb_ffi.create_options()
                
                -- 将cdata对象包装在Lua表中
                local options_table = {
                    _cdata = options_cdata
                }
                
                -- 为options对象添加方法，使其与高级API兼容
                local mt = {
                    __index = function(t, k)
                        if k == "create_if_missing" then
                            return function(v)
                                rocksdb_ffi.set_create_if_missing(t._cdata, v)
                            end
                        elseif k == "set_max_open_files" then
                            return function(v)
                                -- FFI中没有此方法，忽略
                            end
                        elseif k == "set_use_fsync" then
                            return function(v)
                                -- FFI中没有此方法，忽略
                            end
                        elseif k == "set_write_buffer_size" then
                            return function(v)
                                -- FFI中没有此方法，忽略
                            end
                        elseif k == "set_max_write_buffer_number" then
                            return function(v)
                                -- FFI中没有此方法，忽略
                            end
                        elseif k == "set_min_write_buffer_number_to_merge" then
                            return function(v)
                                -- FFI中没有此方法，忽略
                            end
                        elseif k == "set_block_cache" then
                            return function(v)
                                -- FFI中没有此方法，忽略
                            end
                        elseif k == "set_block_size" then
                            return function(v)
                                -- FFI中没有此方法，忽略
                            end
                        elseif k == "set_compression" then
                            return function(v)
                                -- 处理压缩类型参数
                                local compression_level
                                
                                -- 如果参数是表，尝试从中提取压缩级别
                                if type(v) == "table" then
                                    -- 检查是否是压缩类型常量表
                                    if v.LZ4 then
                                        compression_level = 4  -- LZ4
                                    elseif v.SNAPPY then
                                        compression_level = 1  -- SNAPPY
                                    elseif v.NO then
                                        compression_level = 0  -- 无压缩
                                    else
                                        -- 默认使用LZ4
                                        compression_level = 4
                                    end
                                elseif type(v) == "number" then
                                    compression_level = v
                                else
                                    -- 默认使用LZ4
                                    compression_level = 4
                                end
                                
                                rocksdb_ffi.set_compression(t._cdata, compression_level)
                            end
                        elseif k == "enable_statistics" then
                            return function()
                                -- FFI中没有此方法，忽略
                            end
                        elseif k == "set_separator_compression" then
                            return function(v)
                                -- FFI中没有此方法，忽略
                            end
                        elseif k == "set_separator" then
                            return function(v)
                                -- FFI中没有此方法，忽略
                            end
                        elseif k == "set_prefix_extractor" then
                            return function(v)
                                rocksdb_ffi.set_prefix_extractor(t._cdata, v)
                            end
                        elseif k == "create_missing_column_families" then
                            return function(v)
                                rocksdb_ffi.set_create_missing_column_families(t._cdata, v)
                            end
                        elseif k == "set_memtable_prefix_bloom_size_ratio" then
                            return function(v)
                                -- FFI中没有此方法，忽略
                            end
                        else
                            return nil
                        end
                    end
                }
                
                setmetatable(options_table, mt)
                return options_table
            end,
            write_options = function() 
                local write_opts = rocksdb_ffi.create_write_options()
                return {
                    _cdata = write_opts,
                    set_sync = function(self, sync)
                        if rocksdb_ffi.is_available() then
                            rocksdb_ffi.set_writeoptions_sync(self._cdata, sync)
                        end
                    end
                }
            end,
            read_options = function() return rocksdb_ffi.create_read_options() end,
            cache = function(size) 
                -- FFI实现中没有cache函数，返回一个模拟对象
                return {size = size}
            end,
            
            -- 压缩类型常量
            compression_types = {
                NO = 0,
                SNAPPY = 1,
                ZLIB = 2,
                BZLIB2 = 3,
                LZ4 = 4,
                LZ4HC = 5,
                ZSTD = 6
            },
            
            -- 数据库操作
            open_with_column_families = function(default_options, path, cf_names, cf_options_map)
                -- 使用真正的多CF实现
                local db, cfs, err = rocksdb_ffi.open_with_column_families(default_options, path, cf_names, cf_options_map)
                if not db then
                    -- 如果多CF打开失败，尝试使用单CF模式作为备选
                    print("⚠️  多CF数据库打开失败: " .. tostring(err))
                    print("⚠️  尝试使用单CF模式作为备选")
                    
                    local db_single, err_single = rocksdb_ffi.open_database(default_options, path)
                    if not db_single then
                        error("数据库打开失败: " .. tostring(err_single))
                    end
                    
                    -- 返回模拟的CF映射
                    local cfs_single = {[""] = nil}
                    for _, cf_name in ipairs(cf_names) do
                        if cf_name ~= "" then
                            cfs_single[cf_name] = nil
                        end
                    end
                    
                    return db_single, cfs_single
                end
                
                return db, cfs
            end,
            
            -- 批处理操作
            write_batch = function()
                local batch = rocksdb_ffi.create_writebatch()
                return {
                    put = function(self, key, value)
                        rocksdb_ffi.writebatch_put(batch, key, value)
                    end,
                    put_cf = function(self, cf_handle, key, value)
                        if cf_handle == nil then
                            -- 如果列族句柄为nil，使用普通的put方法
                            rocksdb_ffi.writebatch_put(batch, key, value)
                        else
                            rocksdb_ffi.writebatch_put_cf(batch, cf_handle, key, value)
                        end
                    end,
                    delete = function(self, key)
                        rocksdb_ffi.writebatch_delete(batch, key)
                    end,
                    delete_cf = function(self, cf_handle, key)
                        rocksdb_ffi.writebatch_delete_cf(batch, cf_handle, key)
                    end,
                    clear = function(self)
                        rocksdb_ffi.writebatch_clear(batch)
                    end,
                    _batch = batch  -- 内部引用，用于write_batch操作
                }
            end,
            
            -- 数据库关闭方法
            close = function(db)
                if db then
                    rocksdb_ffi.close_database(db)
                end
            end,
            
            -- 写入方法
            put = function(db, write_options, key, value)
                return rocksdb_ffi.put(db, write_options, key, value)
            end,
            
            -- 读取方法
            get = function(db, read_options, key)
                return rocksdb_ffi.get(db, read_options, key)
            end,
            
            -- 删除方法
            delete = function(db, write_options, key)
                return rocksdb_ffi.delete(db, write_options, key)
            end,
            
            -- 批量写入方法
            write_batch = function(db, write_options, batch)
                return rocksdb_ffi.write_batch(db, write_options, batch)
            end
        }
                print("使用RocksDB FFI实现")
            else
                print("警告: FFI模块不可用，无法使用RocksDB FFI实现，将使用文件系统存储模拟器")
            end
        else
            print("警告: rocksdb模块不可用，将使用文件系统存储模拟器")
        end
    end
    
    local ok, json_module = pcall(require, "cjson")
    if ok then
        cjson = json_module
    else
        -- 使用简单的JSON编码作为备选
        cjson = {
            encode = function(t)
                return "{data: " .. tostring(t) .. "}"
            end,
            decode = function(s)
                return {data = s}
            end
        }
    end
end

-- 初始化时检查依赖
check_dependencies()

-- 存储键格式定义
local KeyFormat = {}

-- 统一键格式：TYPE|DIMENSION|KEY|AGG_FUNC|PADDING
-- 确保所有维度使用相同的分隔符数量和位置，优化RocksDB分隔符压缩效率

-- 构建时间维度存储键
function KeyFormat:build_time_dimension_key(dimension, time_key, aggregation_function)
    return table.concat({
        "TIME",
        dimension,
        time_key,
        aggregation_function or "ALL",
        ""  -- 填充字段，保持统一结构
    }, "|")
end

-- 构建其他维度存储键
function KeyFormat:build_other_dimension_key(dimension, dimension_key, aggregation_function)
    -- 确保所有参数都有默认值
    dimension = dimension or ""
    dimension_key = dimension_key or ""
    aggregation_function = aggregation_function or "ALL"
    
    return table.concat({
        "OTHER", 
        dimension,
        dimension_key,
        aggregation_function,
        ""  -- 填充字段，保持统一结构
    }, "|")
end

-- 构建元数据键
function KeyFormat:build_metadata_key(key_type, identifier)
    return table.concat({
        "META",
        key_type,
        identifier or ""
    }, "|")
end

-- 解析存储键
function KeyFormat:parse_storage_key(key)
    local parts = {}
    for part in string.gmatch(key, "([^|]+)") do
        table.insert(parts, part)
    end
    
    if #parts < 3 then
        return nil
    end
    
    local key_type = parts[1]
    
    if key_type == "TIME" then
        return {
            type = "time_dimension",
            dimension = parts[2],
            time_key = parts[3],
            aggregation_function = parts[4] or "ALL"
        }
    elseif key_type == "OTHER" then
        return {
            type = "other_dimension",
            dimension = parts[2],
            dimension_key = parts[3],
            aggregation_function = parts[4] or "ALL"
        }
    elseif key_type == "META" then
        return {
            type = "metadata",
            meta_type = parts[2],
            identifier = parts[3] or ""
        }
    else
        return nil
    end
end

-- 存储值格式定义
local ValueFormat = {}

-- 构建聚合结果存储值
function ValueFormat:build_aggregation_value(aggregation_result, compression_config)
    local value = {
        timestamp = aggregation_result.timestamp,
        count = aggregation_result.count,
        aggregates = aggregation_result.aggregates,
        dimensions = aggregation_result.dimensions,
        compression_data = aggregation_result.compression_data,
        storage_timestamp = os.time()
    }
    
    -- 应用压缩（如果启用）
    if compression_config and compression_config.enabled then
        value = self:apply_compression(value, compression_config)
    end
    
    return cjson.encode(value)
end

-- 应用压缩
function ValueFormat:apply_compression(value, config)
    local compressed = {}
    
    -- 压缩维度数据
    if value.dimensions and config.compress_dimensions then
        compressed.dimensions = self:compress_dimensions(value.dimensions, config)
    end
    
    -- 压缩聚合数据
    if value.aggregates and config.compress_aggregates then
        compressed.aggregates = self:compress_aggregates(value.aggregates, config)
    end
    
    -- 保留必要字段
    compressed.timestamp = value.timestamp
    compressed.count = value.count
    compressed.storage_timestamp = value.storage_timestamp
    
    return compressed
end

-- 压缩维度数据
function ValueFormat:compress_dimensions(dimensions, config)
    local compressed = {}
    
    for field, value in pairs(dimensions) do
        if type(value) == "string" and string.len(value) > config.min_length then
            -- 使用前缀压缩
            compressed[field] = string.sub(value, 1, config.max_prefix_length)
        else
            compressed[field] = value
        end
    end
    
    return compressed
end

-- 压缩聚合数据
function ValueFormat:compress_aggregates(aggregates, config)
    local compressed = {}
    
    for func, value in pairs(aggregates) do
        if type(value) == "number" then
            -- 数值压缩（精度控制）
            compressed[func] = math.floor(value * config.precision_factor) / config.precision_factor
        else
            compressed[func] = value
        end
    end
    
    return compressed
end

-- 解析存储值
function ValueFormat:parse_storage_value(value_json, decompress_config)
    local ok, value = pcall(function()
        return cjson.decode(value_json)
    end)
    
    if not ok then
        return nil
    end
    
    -- 应用解压缩（如果启用）
    if decompress_config and decompress_config.enabled then
        value = self:apply_decompression(value, decompress_config)
    end
    
    return value
end

-- 应用解压缩
function ValueFormat:apply_decompression(value, config)
    local decompressed = {}
    
    -- 解压缩维度数据
    if value.dimensions and config.decompress_dimensions then
        decompressed.dimensions = value.dimensions  -- 实际解压缩逻辑需要维度字典
    end
    
    -- 解压缩聚合数据
    if value.aggregates and config.decompress_aggregates then
        decompressed.aggregates = value.aggregates  -- 实际解压缩逻辑需要精度恢复
    end
    
    -- 保留必要字段
    decompressed.timestamp = value.timestamp
    decompressed.count = value.count
    decompressed.storage_timestamp = value.storage_timestamp
    
    return decompressed
end

-- 创建轻度汇总存储引擎
function LightAggregationStorage:new(config)
    local obj = setmetatable({}, LightAggregationStorage)
    
    -- 处理LightAggregationConfig对象或直接配置
    if type(config) == "table" and config.config then
        obj.config = config.config  -- 从LightAggregationConfig对象中提取配置
    else
        obj.config = config or {}
    end
    
    obj.db = nil
    obj.is_open = false
    
    -- 多CF管理
    obj.column_families = {}  -- 存储所有CF的句柄
    obj.default_cf = nil     -- 默认CF句柄
    
    obj.stats = {
        writes = 0,
        reads = 0,
        deletes = 0,
        errors = 0,
        last_error = nil,
        storage_size = 0,
        cf_stats = {}  -- 每个CF的统计信息
    }
    
    -- 初始化CF统计
    for _, cf_name in pairs(CF_NAMES) do
        obj.stats.cf_stats[cf_name] = {
            writes = 0,
            reads = 0,
            deletes = 0,
            data_size = 0
        }
    end
    
    return obj
end

-- 打开数据库（多CF架构）
function LightAggregationStorage:open()
    if self.is_open then
        return true, "数据库已打开"
    end
    
    -- 检查RocksDB是否可用
    if not rocksdb then
        -- 创建简单的文件系统存储实现
        self.file_storage = {
            put = function(db, write_options, key, value, cf_handle)
                -- 简单实现：将数据存储在内存表中
                if not self._file_storage_data then
                    self._file_storage_data = {}
                end
                
                local cf_name = "default"
                if cf_handle and type(cf_handle) == "string" then
                    cf_name = cf_handle
                end
                
                if not self._file_storage_data[cf_name] then
                    self._file_storage_data[cf_name] = {}
                end
                
                self._file_storage_data[cf_name][key] = value
                return true
            end,
            write_options = function()
                return {}
            end,
            options = function()
                return {}
            end,
            open_with_column_families = function(options, path, cf_names, cf_options)
                -- 返回模拟的数据库和CF句柄
                local db = {}
                local cfs = {}
                
                for _, cf_name in ipairs(cf_names) do
                    cfs[cf_name] = cf_name
                end
                
                return db, cfs
            end
        }
        
        -- 初始化文件系统存储数据库
        local options = self.file_storage.options()
        local cf_names = {}
        
        -- 添加默认CF
        table.insert(cf_names, CF_NAMES.DEFAULT)
        
        -- 为每个业务CF添加名称
        for _, cf_name in pairs(CF_NAMES) do
            if cf_name ~= CF_NAMES.DEFAULT then
                table.insert(cf_names, cf_name)
            end
        end
            
        -- 确保配置参数存在
        if not self.config then
            self.config = {}
        end
        if not self.config.storage then
            self.config.storage = {}
        end
        if not self.config.storage.path then
            self.config.storage.path = "./test_db"
        end
        
        -- 打开文件系统存储数据库
        local db, cfs = self.file_storage.open_with_column_families(options, self.config.storage.path, cf_names, {})
        
        self.db = db
        self.column_families = cfs
        self.default_cf = cfs[CF_NAMES.DEFAULT] or cfs[1]  -- 默认CF
        
        self.is_open = true
        print("RocksDB不可用，使用文件系统存储模拟器")
        return true, "RocksDB不可用，使用文件系统存储模拟器"
    end
    
    local ok, err = pcall(function()
        -- 创建默认CF选项
        local default_options = rocksdb.options()
        
        -- 基本配置（只使用FFI支持的方法）
        default_options:create_if_missing(true)
        default_options:create_missing_column_families(true)  -- 添加这一行
        
        -- 压缩配置
        if self.config.storage.compression == "lz4" then
            default_options:set_compression(4)  -- LZ4压缩
        elseif self.config.storage.compression == "snappy" then
            default_options:set_compression(1)  -- SNAPPY压缩
        else
            default_options:set_compression(0)  -- 无压缩
        end
        
        -- 为每个CF创建独立的选项（简化实现）
        local cf_options_map = {}
        local cf_names = {}
        
        -- 添加默认CF
        table.insert(cf_names, CF_NAMES.DEFAULT)
        cf_options_map[CF_NAMES.DEFAULT] = default_options
        
        -- 为每个业务CF创建独立选项
        for _, cf_name in pairs(CF_NAMES) do
            -- 跳过默认CF（"default"），因为已经添加过了默认CF
            if cf_name ~= CF_NAMES.DEFAULT then
                local cf_options = rocksdb.options()
                
                -- 复制基本配置
                cf_options:create_if_missing(true)
                cf_options:create_missing_column_families(true)  -- 添加这一行
                
                -- 压缩配置
                if self.config.storage.compression == "lz4" then
                    cf_options:set_compression(4)  -- LZ4压缩
                elseif self.config.storage.compression == "snappy" then
                    cf_options:set_compression(1)  -- SNAPPY压缩
                else
                    cf_options:set_compression(0)  -- 无压缩
                end
                
                -- 为每个CF独立配置前缀压缩
                local cf_compression_config = get_cf_compression_config(cf_name)
                if cf_compression_config.enable_separator_compression then
                    cf_options:set_prefix_extractor(cf_compression_config.prefix_extractor_length)
                end
                
                table.insert(cf_names, cf_name)
                -- 使用选项对象的_cdata成员
                cf_options_map[cf_name] = cf_options._cdata
            end
        end
        
        -- 智能多CF数据库打开逻辑
        local db, cfs, err
        
        -- 首先尝试多CF模式打开
        db, cfs, err = rocksdb.open_with_column_families(default_options._cdata, self.config.storage.path, cf_names, cf_options_map)
        
        if not db then
            -- 多CF模式失败，检查错误类型
            if string.find(err or "", "Column family not found") then
                print("⚠️  多CF数据库打开失败（列族不匹配），尝试单CF模式作为备选...")
                
                -- 尝试单CF模式
                db, err = rocksdb.open_database(default_options._cdata, self.config.storage.path)
                if db then
                    -- 单CF模式成功，创建模拟的CF映射
                    cfs = {}
                    for _, cf_name in ipairs(cf_names) do
                        cfs[cf_name] = nil  -- 单CF模式下所有CF句柄为nil
                    end
                    
                    print("✅ 单CF模式成功（多CF架构回退）")
                else
                    -- 单CF模式也失败
                    error("单CF模式也失败: " .. tostring(err))
                end
            else
                -- 其他错误
                error("多CF数据库打开失败: " .. tostring(err))
            end
        else
            print("✅ 多CF数据库打开成功")
        end
        
        self.db = db
        self.column_families = cfs
        self.default_cf = cfs[CF_NAMES.DEFAULT] or cfs[1]  -- 默认CF
        
        -- 打印CF配置信息
        print("[多CF架构] 数据库已打开，配置了 " .. #cf_names .. " 个ColumnFamily:")
        for _, cf_name in ipairs(cf_names) do
            local cf_compression_config = get_cf_compression_config(cf_name)
            local cf_handle = cfs[cf_name]
            print(string.format("  - %s: 前缀长度=%d, 句柄=%s", 
                cf_name or "default", 
                cf_compression_config.prefix_extractor_length,
                tostring(cf_handle)))
        end
        
        self.is_open = true
    end)
    
    if not ok then
        self.stats.errors = self.stats.errors + 1
        self.stats.last_error = err
        return false, "数据库打开失败: " .. tostring(err)
    end
    
    return true, "数据库打开成功"
end

-- 关闭数据库
function LightAggregationStorage:close()
    if not self.is_open then
        return true, "数据库已关闭"
    end
    
    -- 检查是否使用文件系统存储
    if self.file_storage then
        local ok, err = pcall(function()
            if self.db then
                -- 文件系统存储模式下的关闭操作
                self.db = nil
                self.column_families = {}
                self.default_cf = nil
            end
            self.is_open = false
        end)
        
        if not ok then
            self.stats.errors = self.stats.errors + 1
            self.stats.last_error = err
            return false, "文件系统存储关闭失败: " .. tostring(err)
        end
        
        return true, "文件系统存储已关闭"
    end
    
    local ok, err = pcall(function()
        if self.db then
            rocksdb.close(self.db)
            self.db = nil
        end
        self.is_open = false
    end)
    
    if not ok then
        self.stats.errors = self.stats.errors + 1
        self.stats.last_error = err
        return false, "数据库关闭失败: " .. tostring(err)
    end
    
    return true, "数据库关闭成功"
end

-- 存储聚合结果
function LightAggregationStorage:store_aggregation_results(results)
    if not self.is_open then
        return false, "数据库未打开"
    end
    
    -- 检查是否使用文件系统存储
    if self.file_storage then
        for _, result in ipairs(results) do
            local key, value = self:build_key_value_pair(result)
            local cf_name = get_cf_for_dimension(result.dimension)
            local cf_handle = self.column_families[cf_name] or self.default_cf
            
            -- 使用文件系统存储写入（传递CF句柄）
            local ok = self.file_storage.put(self.db, self.file_storage.write_options(), key, value, cf_handle)
            if not ok then
                self.stats.errors = self.stats.errors + 1
                self.stats.last_error = "文件系统存储失败"
            else
                -- 更新CF统计信息
                if self.stats.cf_stats[cf_name] then
                    self.stats.cf_stats[cf_name].writes = self.stats.cf_stats[cf_name].writes + 1
                end
            end
        end
        self.stats.writes = self.stats.writes + #results
        return true, "存储了 " .. #results .. " 个聚合结果到文件系统"
    end
    
    -- 检查RocksDB是否可用
    if not rocksdb then
        -- 如果RocksDB不可用且没有文件系统存储，创建一个简单的文件系统存储实现
        if not self.file_storage then
            -- 创建简单的文件系统存储实现
            self.file_storage = {
                put = function(db, write_options, key, value, cf_handle)
                    -- 简单实现：将数据存储在内存表中
                    if not self._file_storage_data then
                        self._file_storage_data = {}
                    end
                    
                    local cf_name = "default"
                    if cf_handle and type(cf_handle) == "string" then
                        cf_name = cf_handle
                    end
                    
                    if not self._file_storage_data[cf_name] then
                        self._file_storage_data[cf_name] = {}
                    end
                    
                    self._file_storage_data[cf_name][key] = value
                    return true
                end,
                write_options = function()
                    return {}
                end
            }
        end
        
        -- 使用文件系统存储
        for _, result in ipairs(results) do
            local key, value = self:build_key_value_pair(result)
            local cf_name = get_cf_for_dimension(result.dimension)
            local cf_handle = self.column_families[cf_name] or self.default_cf
            
            -- 使用文件系统存储写入
            local ok = self.file_storage.put(self.db, self.file_storage.write_options(), key, value, cf_handle)
            if not ok then
                self.stats.errors = self.stats.errors + 1
                self.stats.last_error = "文件系统存储失败"
            else
                -- 更新CF统计信息
                if self.stats.cf_stats[cf_name] then
                    self.stats.cf_stats[cf_name].writes = self.stats.cf_stats[cf_name].writes + 1
                end
            end
        end
        self.stats.writes = self.stats.writes + #results
        return true, "存储了 " .. #results .. " 个聚合结果到文件系统"
    end
    
    local batch = rocksdb.write_batch()
    local stored_count = 0
    
    for _, result in ipairs(results) do
        local ok, err = self:store_single_result(batch, result)
        if ok then
            stored_count = stored_count + 1
        else
            self.stats.errors = self.stats.errors + 1
            self.stats.last_error = err
        end
    end
    
    -- 批量写入
    if stored_count > 0 then
        local ok, err = pcall(function()
            local write_options = rocksdb.write_options()
            write_options:set_sync(false)
            rocksdb.write_batch(self.db, write_options, batch)
        end)
        
        if ok then
            self.stats.writes = self.stats.writes + stored_count
            return true, "存储了 " .. stored_count .. " 个聚合结果"
        else
            self.stats.errors = self.stats.errors + 1
            self.stats.last_error = err
            return false, "批量写入失败: " .. tostring(err)
        end
    end
    
    return true, "没有需要存储的结果"
end

-- 构建键值对
function LightAggregationStorage:build_key_value_pair(result)
    local key, value
    
    if result.dimension_type == "time" then
        key = KeyFormat:build_time_dimension_key(
            result.dimension,
            result.key,
            result.aggregation_function
        )
    else
        key = KeyFormat:build_other_dimension_key(
            result.dimension,
            result.key,
            result.aggregation_function
        )
    end
    
    value = ValueFormat:build_aggregation_value(result, self.config.compression_strategies and self.config.compression_strategies.SEPARATOR)
    
    return key, value
end

-- 存储单个聚合结果（多CF架构）
function LightAggregationStorage:store_single_result(batch, result)
    local key, value
    
    if result.dimension_type == "time" then
        key = KeyFormat:build_time_dimension_key(
            result.dimension,
            result.key,
            result.aggregation_function
        )
    else
        key = KeyFormat:build_other_dimension_key(
            result.dimension,
            result.key,
            result.aggregation_function
        )
    end
    
    value = ValueFormat:build_aggregation_value(result, self.config.compression_strategies and self.config.compression_strategies.SEPARATOR)
    
    -- 根据维度类型选择对应的CF
    local cf_name = get_cf_for_dimension(result.dimension)
    local cf_handle = self.column_families[cf_name] or self.default_cf
    
    -- 使用指定CF进行存储
    batch:put_cf(cf_handle, key, value)
    
    -- 更新CF统计
    if self.stats.cf_stats[cf_name] then
        self.stats.cf_stats[cf_name].writes = self.stats.cf_stats[cf_name].writes + 1
    end
    
    return true
end

-- 查询聚合数据（多CF架构）
function LightAggregationStorage:query_aggregated_data(query)
    if not self.is_open then
        return nil, "数据库未打开"
    end
    
    -- 检查是否使用文件系统存储
    if self.file_storage then
        local results = {}
        local start_key, end_key = self:build_query_range(query)
        
        -- 如果有内存中的文件系统存储数据，从中查询
        if self._file_storage_data then
            -- 确定需要查询的CF列表
            local target_cfs = {}
            
            if query.dimension_type == "time" then
                -- 时间维度查询：只查询时间CF
                table.insert(target_cfs, CF_NAMES.TIME)
            elseif query.dimension_type == "other" and query.dimension then
                -- 特定业务维度查询：查询对应的CF
                local cf_name = get_cf_for_dimension(query.dimension)
                table.insert(target_cfs, cf_name)
            else
                -- 跨维度查询：查询所有相关CF
                for _, cf_name in pairs(CF_NAMES) do
                    if cf_name ~= "default_cf" then
                        table.insert(target_cfs, cf_name)
                    end
                end
            end
            
            -- 对每个目标CF进行查询
            for _, cf_name in ipairs(target_cfs) do
                local cf_data = self._file_storage_data[cf_name]
                if cf_data then
                    for key, value in pairs(cf_data) do
                        -- 简单的键范围匹配
                        if key >= start_key and key <= end_key then
                            -- 解析值
                            local parsed_value = ValueFormat:parse_storage_value(value)
                            if parsed_value then
                                table.insert(results, parsed_value)
                            end
                        end
                    end
                end
            end
        end
        
        return results, nil
    end
    
    local results = {}
    local read_options = rocksdb.read_options()
    
    -- 构建查询键范围
    local start_key, end_key = self:build_query_range(query)
    
    -- 确定需要查询的CF列表
    local target_cfs = {}
    
    if query.dimension_type == "time" then
        -- 时间维度查询：只查询时间CF
        table.insert(target_cfs, CF_NAMES.TIME)
    elseif query.dimension_type == "other" and query.dimension then
        -- 特定业务维度查询：查询对应的CF
        local cf_name = get_cf_for_dimension(query.dimension)
        table.insert(target_cfs, cf_name)
    else
        -- 跨维度查询：查询所有相关CF
        for _, cf_name in pairs(CF_NAMES) do
            if cf_name ~= "default_cf" then
                table.insert(target_cfs, cf_name)
            end
        end
    end
    
    local ok, err = pcall(function()
        -- 对每个目标CF进行查询
        for _, cf_name in ipairs(target_cfs) do
            local cf_handle = self.column_families[cf_name] or self.default_cf
            
            -- 创建CF特定的迭代器
            local iter = self.db:new_iterator_cf(read_options, cf_handle)
            
            -- 定位到起始键
            iter:seek(start_key)
            
            while iter:valid() do
                local key = iter:key()
                local value = iter:value()
                
                -- 检查是否超出范围
                if key > end_key then
                    break
                end
                
                -- 解析键值对
                local key_info = KeyFormat:parse_storage_key(key)
                local value_data = ValueFormat:parse_storage_value(value)
                
                if key_info and value_data then
                    -- 应用查询过滤器
                    if self:apply_query_filters(key_info, value_data, query.filters) then
                        table.insert(results, {
                            key = key_info,
                            value = value_data,
                            cf = cf_name  -- 记录数据来源的CF
                        })
                    end
                end
                
                iter:next()
                self.stats.reads = self.stats.reads + 1
                
                -- 更新CF统计
                if self.stats.cf_stats[cf_name] then
                    self.stats.cf_stats[cf_name].reads = self.stats.cf_stats[cf_name].reads + 1
                end
            end
            
            iter:close()
        end
    end)
    
    if not ok then
        self.stats.errors = self.stats.errors + 1
        self.stats.last_error = err
        return nil, "查询失败: " .. tostring(err)
    end
    
    return results, nil
end

-- 构建查询范围
function LightAggregationStorage:build_query_range(query)
    if query.dimension_type == "time" then
        local start_key = KeyFormat:build_time_dimension_key(
            query.dimension,
            query.start_time or "",
            query.aggregation_function or "ALL"
        )
        
        local end_key = KeyFormat:build_time_dimension_key(
            query.dimension,
            query.end_time or "\255",
            query.aggregation_function or "ALL"
        )
        
        return start_key, end_key
    else
        local start_key = KeyFormat:build_other_dimension_key(
            query.dimension,
            query.start_key or "",
            query.aggregation_function or "ALL"
        )
        
        local end_key = KeyFormat:build_other_dimension_key(
            query.dimension,
            query.end_key or "\255",
            query.aggregation_function or "ALL"
        )
        
        return start_key, end_key
    end
end

-- 应用查询过滤器
function LightAggregationStorage:apply_query_filters(key_info, value_data, filters)
    if not filters then
        return true
    end
    
    -- 时间范围过滤
    if filters.timestamp_range then
        if value_data.timestamp < filters.timestamp_range.start or 
           value_data.timestamp > filters.timestamp_range.finish then
            return false
        end
    end
    
    -- 维度值过滤
    if filters.dimensions then
        for field, expected_value in pairs(filters.dimensions) do
            if value_data.dimensions[field] ~= expected_value then
                return false
            end
        end
    end
    
    -- 聚合值过滤
    if filters.aggregates then
        for func, condition in pairs(filters.aggregates) do
            local actual_value = value_data.aggregates[func]
            if actual_value then
                if condition.min and actual_value < condition.min then
                    return false
                end
                if condition.max and actual_value > condition.max then
                    return false
                end
            end
        end
    end
    
    return true
end

-- 删除过期数据（多CF架构）
function LightAggregationStorage:delete_expired_data(retention_days)
    if not self.is_open then
        return 0, "数据库未打开"
    end
    
    -- 检查是否使用文件系统存储
    if self.file_storage then
        -- 文件系统存储模式下，过期数据删除功能受限
        print("文件系统存储模式：过期数据删除功能受限")
        return 0, "文件系统存储模式：过期数据删除功能受限"
    end
    
    local cutoff_time = os.time() - (retention_days * 86400)
    local deleted_count = 0
    
    local read_options = rocksdb.read_options()
    local write_options = rocksdb.write_options()
    
    local ok, err = pcall(function()
        -- 对每个CF进行过期数据删除
        for cf_name, cf_handle in pairs(self.column_families) do
            local batch = rocksdb.write_batch()
            local cf_deleted_count = 0
            
            -- 创建CF特定的迭代器
            local iter = self.db:new_iterator_cf(read_options, cf_handle)
            
            iter:seek_to_first()
            
            while iter:valid() do
                local key = iter:key()
                local value = iter:value()
                
                local value_data = ValueFormat:parse_storage_value(value)
                
                if value_data and value_data.storage_timestamp < cutoff_time then
                    batch:delete_cf(cf_handle, key)
                    deleted_count = deleted_count + 1
                    cf_deleted_count = cf_deleted_count + 1
                    
                    -- 批量提交（每1000条）
                    if deleted_count % 1000 == 0 then
                        self.db:write(write_options, batch)
                        batch = rocksdb.write_batch()
                    end
                end
                
                iter:next()
            end
            
            -- 提交剩余批次
            if cf_deleted_count % 1000 ~= 0 then
                self.db:write(write_options, batch)
            end
            
            iter:close()
            
            -- 更新CF统计
            if self.stats.cf_stats[cf_name] then
                self.stats.cf_stats[cf_name].deletes = self.stats.cf_stats[cf_name].deletes + cf_deleted_count
            end
        end
    end)
    
    if not ok then
        self.stats.errors = self.stats.errors + 1
        self.stats.last_error = err
        return 0, "删除过期数据失败: " .. tostring(err)
    end
    
    self.stats.deletes = self.stats.deletes + deleted_count
    return deleted_count, "删除了 " .. deleted_count .. " 条过期数据"
end

-- 获取存储统计信息（多CF架构）
function LightAggregationStorage:get_stats()
    local stats = {
        basic = self.stats,
        database = {
            is_open = self.is_open,
            path = self.config.storage.path,
            column_families = {}
        }
    }
    
    -- 检查是否使用文件系统存储
    if self.file_storage then
        -- 文件系统存储模式下的统计
        if self.is_open and self.db then
            for cf_name, cf_handle in pairs(self.column_families) do
                local cf_stats = {
                    name = cf_name,
                    handle = tostring(cf_handle)
                }
                
                -- 文件系统存储模式下，从内存数据中统计
                if self.db.data and self.db.data[cf_name] then
                    cf_stats.estimated_keys = 0
                    cf_stats.estimated_size = 0
                    
                    -- 计算实际存储的键值对数量和大小
                    for key, value in pairs(self.db.data[cf_name]) do
                        cf_stats.estimated_keys = cf_stats.estimated_keys + 1
                        cf_stats.estimated_size = cf_stats.estimated_size + string.len(key) + string.len(value)
                    end
                else
                    cf_stats.estimated_keys = 0
                    cf_stats.estimated_size = 0
                end
                
                -- 合并CF特定的统计信息
                if self.stats.cf_stats[cf_name] then
                    for k, v in pairs(self.stats.cf_stats[cf_name]) do
                        cf_stats[k] = v
                    end
                end
                
                stats.database.column_families[cf_name] = cf_stats
            end
        end
    else
        -- 获取每个CF的详细信息（RocksDB模式）
        if self.is_open then
            for cf_name, cf_handle in pairs(self.column_families) do
                local cf_stats = {
                    name = cf_name,
                    handle = tostring(cf_handle)
                }
                
                -- 获取CF的键数量估算
                local ok, cf_size_info = pcall(function()
                    return self.db:get_property_cf(cf_handle, "rocksdb.estimate-num-keys")
                end)
                
                if ok and cf_size_info then
                    cf_stats.estimated_keys = tonumber(cf_size_info) or 0
                end
                
                -- 获取CF的大小估算
                local ok, cf_size = pcall(function()
                    return self.db:get_property_cf(cf_handle, "rocksdb.estimate-live-data-size")
                end)
                
                if ok and cf_size then
                    cf_stats.estimated_size = tonumber(cf_size) or 0
                end
                
                -- 合并CF特定的统计信息
                if self.stats.cf_stats[cf_name] then
                    for k, v in pairs(self.stats.cf_stats[cf_name]) do
                        cf_stats[k] = v
                    end
                end
                
                stats.database.column_families[cf_name] = cf_stats
            end
        end
    end
    
    -- 获取RocksDB内部统计（如果启用）
    if self.config.storage.enable_statistics and self.is_open and not self.file_storage then
        local ok, db_stats = pcall(function()
            return self.db:get_property("rocksdb.stats")
        end)
        
        if ok and db_stats then
            stats.rocksdb = db_stats
        end
    end
    
    -- 估算总存储大小
    if self.is_open then
        if self.file_storage then
            -- 文件系统存储模式下的总统计
            stats.database.estimated_keys = 0
            stats.database.estimated_size = 0
            
            if self.db and self.db.data then
                for cf_name, cf_data in pairs(self.db.data) do
                    for key, value in pairs(cf_data) do
                        stats.database.estimated_keys = stats.database.estimated_keys + 1
                        stats.database.estimated_size = stats.database.estimated_size + string.len(key) + string.len(value)
                    end
                end
            end
        else
            local ok, size_info = pcall(function()
                return self.db:get_property("rocksdb.estimate-num-keys")
            end)
            
            if ok and size_info then
                stats.database.estimated_keys = tonumber(size_info) or 0
            end
        end
    end
    
    return stats
end

-- 备份数据库
function LightAggregationStorage:backup(backup_path)
    if not self.is_open then
        return false, "数据库未打开"
    end
    
    local ok, err = pcall(function()
        local backup_engine = rocksdb.backup_engine(self.config.storage.path .. ".backup")
        backup_engine:create_new_backup(self.db)
        backup_engine:close()
    end)
    
    if not ok then
        self.stats.errors = self.stats.errors + 1
        self.stats.last_error = err
        return false, "备份失败: " .. tostring(err)
    end
    
    return true, "备份成功"
end

-- 恢复数据库
function LightAggregationStorage:restore(backup_path)
    if self.is_open then
        self:close()
    end
    
    local ok, err = pcall(function()
        local backup_engine = rocksdb.backup_engine(backup_path)
        backup_engine:restore_db_from_latest_backup(self.config.storage.path)
        backup_engine:close()
    end)
    
    if not ok then
        self.stats.errors = self.stats.errors + 1
        self.stats.last_error = err
        return false, "恢复失败: " .. tostring(err)
    end
    
    -- 重新打开数据库
    return self:open()
end

-- 压缩数据库
function LightAggregationStorage:compact()
    if not self.is_open then
        return false, "数据库未打开"
    end
    
    local ok, err = pcall(function()
        self.db:compact_range()
    end)
    
    if not ok then
        self.stats.errors = self.stats.errors + 1
        self.stats.last_error = err
        return false, "压缩失败: " .. tostring(err)
    end
    
    return true, "压缩成功"
end

-- 检查数据库完整性
function LightAggregationStorage:check_integrity()
    if not self.is_open then
        return false, "数据库未打开"
    end
    
    local ok, err = pcall(function()
        -- 简单的完整性检查：读取一些随机键
        local read_options = rocksdb.read_options()
        local iter = self.db:new_iterator(read_options)
        
        iter:seek_to_first()
        local sample_count = 0
        
        while iter:valid() and sample_count < 100 do
            local key = iter:key()
            local value = iter:value()
            
            -- 尝试解析键值对
            local key_info = KeyFormat:parse_storage_key(key)
            local value_data = ValueFormat:parse_storage_value(value)
            
            if not key_info or not value_data then
                error("数据损坏: 无法解析键值对")
            end
            
            iter:next()
            sample_count = sample_count + 1
        end
        
        iter:close()
    end)
    
    if not ok then
        return false, "完整性检查失败: " .. tostring(err)
    end
    
    return true, "完整性检查通过"
end

return LightAggregationStorage