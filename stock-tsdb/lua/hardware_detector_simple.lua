-- 简化版硬件信息检测器
-- 用于检测系统硬件信息并自动优化RocksDB参数

local HardwareDetector = {}
HardwareDetector.__index = HardwareDetector

function HardwareDetector:new()
    local obj = setmetatable({}, HardwareDetector)
    obj.cpu_info = nil
    obj.memory_info = nil
    obj.disk_info = nil
    obj.os_type = nil
    
    -- 检测操作系统类型
    obj:detect_os_type()
    
    return obj
end

-- 检测操作系统类型
function HardwareDetector:detect_os_type()
    -- 使用更简单的方式检测操作系统
    local handle = io.popen("uname -s")
    if handle then
        local result = handle:read("*line")
        handle:close()
        
        if result == "Linux" then
            self.os_type = "linux"
        elseif result == "Darwin" then
            self.os_type = "macos"
        else
            self.os_type = "unknown"
        end
    else
        self.os_type = "unknown"
    end
    
    return self.os_type
end

-- 获取CPU信息
function HardwareDetector:get_cpu_info()
    if self.cpu_info then
        return self.cpu_info
    end
    
    local cpu_info = {
        cores = 0,
        model = "unknown",
        frequency = "unknown"
    }
    
    if self.os_type == "macos" then
        -- macOS系统获取CPU核心数
        local handle = io.popen("sysctl -n machdep.cpu.core_count")
        if handle then
            local cores = tonumber(handle:read("*line"))
            handle:close()
            cpu_info.cores = cores or 0
        end
        
        -- 获取CPU型号
        handle = io.popen("sysctl -n machdep.cpu.brand_string")
        if handle then
            local model = handle:read("*line")
            handle:close()
            cpu_info.model = model or "unknown"
        end
        
        -- 获取CPU频率
        handle = io.popen("sysctl -n hw.cpufrequency_max")
        if handle then
            local freq = tonumber(handle:read("*line"))
            handle:close()
            if freq then
                cpu_info.frequency = string.format("%.2f GHz", freq / 1000000000)
            end
        end
    else
        -- Linux或其他系统
        -- 使用nproc命令获取CPU核心数
        local handle = io.popen("nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null")
        if handle then
            local cores = tonumber(handle:read("*line"))
            handle:close()
            cpu_info.cores = cores or 0
        end
        
        -- 获取CPU型号（简化版）
        cpu_info.model = "Unknown CPU Model"
        cpu_info.frequency = "Unknown Frequency"
    end
    
    -- 如果无法获取核心数，使用默认值
    if cpu_info.cores == 0 then
        cpu_info.cores = 4  -- 默认4核心
    end
    
    self.cpu_info = cpu_info
    return cpu_info
end

-- 获取内存信息
function HardwareDetector:get_memory_info()
    if self.memory_info then
        return self.memory_info
    end
    
    local memory_info = {
        total = 0,
        available = 0,
        used = 0
    }
    
    if self.os_type == "macos" then
        -- macOS系统获取总内存
        local handle = io.popen("sysctl -n hw.memsize")
        if handle then
            local total = tonumber(handle:read("*line"))
            handle:close()
            memory_info.total = total or 0
        end
        
        -- 估算可用内存（简化版）
        memory_info.available = memory_info.total * 0.7  -- 假设70%可用
        memory_info.used = memory_info.total - memory_info.available
    else
        -- Linux系统
        local handle = io.popen("free -b | grep Mem")
        if handle then
            local output = handle:read("*line")
            handle:close()
            
            -- 简单解析free命令输出
            local parts = {}
            for part in output:gmatch("%S+") do
                table.insert(parts, part)
            end
            
            if #parts >= 3 then
                memory_info.total = tonumber(parts[2]) or 0
                memory_info.used = tonumber(parts[3]) or 0
                memory_info.available = memory_info.total - memory_info.used
            end
        end
    end
    
    -- 如果无法获取内存信息，使用默认值
    if memory_info.total == 0 then
        memory_info.total = 8 * 1024 * 1024 * 1024  -- 默认8GB
        memory_info.available = 6 * 1024 * 1024 * 1024  -- 默认6GB可用
        memory_info.used = 2 * 1024 * 1024 * 1024  -- 默认2GB已用
    end
    
    self.memory_info = memory_info
    return memory_info
end

-- 检测磁盘是否为SSD
function HardwareDetector:is_ssd(disk_path)
    disk_path = disk_path or "/"
    
    -- 简化版检测，假设现代系统使用SSD
    -- 在实际生产环境中，应该使用更精确的检测方法
    if self.os_type == "macos" then
        local handle = io.popen("diskutil info $(df -h / | tail -1 | awk '{print $1}') | grep 'Solid State'")
        if handle then
            local output = handle:read("*all")
            handle:close()
            return output:find("Yes") ~= nil
        end
    elseif self.os_type == "linux" then
        -- 尝试从/proc/diskstats或其他方式检测，但这里简化处理
        local handle = io.popen("cat /sys/block/sda/queue/rotational 2>/dev/null || echo 1")
        if handle then
            local rotational = tonumber(handle:read("*line"))
            handle:close()
            return rotational == 0
        end
    end
    
    -- 默认假设为SSD（现代系统常见）
    return true
end

-- 获取磁盘信息
function HardwareDetector:get_disk_info(disk_path)
    disk_path = disk_path or "/"
    
    if self.disk_info and self.disk_info.path == disk_path then
        return self.disk_info
    end
    
    local disk_info = {
        path = disk_path,
        total = 0,
        free = 0,
        used = 0,
        is_ssd = self:is_ssd(disk_path)
    }
    
    -- 检查目录是否存在，如果不存在则使用根目录
    local dir_exists = false
    local handle = io.popen("[ -d '" .. disk_path .. "' ] && echo 'exists' || echo 'not_exists'")
    if handle then
        local result = handle:read("*line")
        handle:close()
        dir_exists = (result == "exists")
    end
    
    -- 使用实际存在的路径获取磁盘空间
    local path_to_check = dir_exists and disk_path or "/"
    
    -- 使用df命令获取磁盘空间
    handle = io.popen("df -k " .. path_to_check .. " | tail -1")
    if handle then
        local output = handle:read("*line")
        handle:close()
        
        if output then
            -- 解析df输出
            local parts = {}
            for part in output:gmatch("%S+") do
                table.insert(parts, part)
            end
            
            if #parts >= 6 then
                disk_info.total = tonumber(parts[2]) * 1024 or 0  -- 转换为字节
                disk_info.used = tonumber(parts[3]) * 1024 or 0
                disk_info.free = tonumber(parts[4]) * 1024 or 0
            end
        end
    end
    
    -- 如果无法获取磁盘信息，使用默认值
    if disk_info.total == 0 then
        disk_info.total = 500 * 1024 * 1024 * 1024  -- 默认500GB
        disk_info.free = 400 * 1024 * 1024 * 1024  -- 默认400GB可用
        disk_info.used = 100 * 1024 * 1024 * 1024  -- 默认100GB已用
    end
    
    self.disk_info = disk_info
    return disk_info
end

-- 根据硬件信息生成RocksDB优化参数
function HardwareDetector:get_optimized_rocksdb_params(data_dir)
    data_dir = data_dir or "./data"
    
    -- 获取硬件信息
    local cpu_info = self:get_cpu_info()
    local memory_info = self:get_memory_info()
    local disk_info = self:get_disk_info(data_dir)
    
    -- 基础参数
    local params = {
        -- 基础配置
        create_if_missing = true,
        
        -- 写入缓冲区配置
        write_buffer_size = 64 * 1024 * 1024,  -- 默认64MB
        max_write_buffer_number = 4,
        
        -- 压缩配置
        compression = 4,  -- LZ4压缩
        
        -- 前缀压缩配置
        enable_prefix_compression = true,
        prefix_extractor_length = 6,  -- 默认6字节前缀
        memtable_prefix_bloom_size_ratio = 0.1,  -- 10%内存用于布隆过滤器
        
        -- 文件大小配置
        target_file_size_base = 64 * 1024 * 1024,  -- 默认64MB
        max_file_size = 128 * 1024 * 1024,  -- 默认128MB
        
        -- 并发配置
        max_background_compactions = 2,
        max_background_flushes = 1,
        
        -- 缓存配置
        block_cache_size = 256 * 1024 * 1024,  -- 默认256MB
        
        -- 性能监控
        enable_statistics = true,
        stats_dump_period_sec = 600,
        
        -- 存储类型标记
        is_ssd = disk_info.is_ssd
    }
    
    -- 根据CPU核心数优化并发参数
    if cpu_info.cores > 0 then
        params.max_background_compactions = math.max(2, math.floor(cpu_info.cores / 4))
        params.max_background_flushes = math.max(1, math.floor(cpu_info.cores / 8))
        params.max_subcompactions = math.max(1, math.floor(cpu_info.cores / 8))
    end
    
    -- 根据内存大小优化缓存和缓冲区
    if memory_info.total > 0 then
        local total_mem_gb = memory_info.total / (1024 * 1024 * 1024)
        
        -- 分配内存的比例
        local block_cache_ratio = 0.25  -- 块缓存使用25%内存
        local write_buffer_ratio = 0.1   -- 写缓冲区使用10%内存
        
        -- 根据内存大小调整比例
        if total_mem_gb < 4 then
            block_cache_ratio = 0.15
            write_buffer_ratio = 0.05
        elseif total_mem_gb > 32 then
            block_cache_ratio = 0.3
            write_buffer_ratio = 0.15
        end
        
        -- 计算具体大小
        params.block_cache_size = math.floor(memory_info.total * block_cache_ratio)
        
        -- 写缓冲区总大小
        local total_write_buffer_size = math.floor(memory_info.total * write_buffer_ratio)
        
        -- 根据写缓冲区总数调整单个缓冲区大小
        if params.max_write_buffer_number > 0 then
            params.write_buffer_size = math.floor(total_write_buffer_size / params.max_write_buffer_number)
            -- 确保写缓冲区至少为16MB
            params.write_buffer_size = math.max(params.write_buffer_size, 16 * 1024 * 1024)
        end
    end
    
    -- 根据是否为SSD优化I/O参数
    if disk_info.is_ssd then
        -- SSD优化参数
        params.target_file_size_base = 128 * 1024 * 1024  -- 增大文件大小
        params.max_file_size = 256 * 1024 * 1024
        params.delayed_write_rate = 8388608  -- 8MB/s
        params.compaction_readahead_size = 0  -- SSD不需要预读取
        params.bytes_per_sync = 0  -- 禁用同步以提高性能
        params.wal_bytes_per_sync = 0
    else
        -- HDD优化参数
        params.target_file_size_base = 32 * 1024 * 1024  -- 减小文件大小
        params.max_file_size = 64 * 1024 * 1024
        params.delayed_write_rate = 16777216  -- 16MB/s
        params.compaction_readahead_size = 2 * 1024 * 1024  -- 2MB预读取
        params.bytes_per_sync = 1048576  -- 1MB同步
        params.wal_bytes_per_sync = 1048576
    end
    
    return params
end

-- 生成优化配置的字符串表示
function HardwareDetector:generate_config_string(params)
    local lines = {"-- 自动生成的RocksDB优化配置"}
    
    for key, value in pairs(params) do
        if type(value) == "string" then
            table.insert(lines, string.format("%s = '%s',", key, value))
        else
            table.insert(lines, string.format("%s = %s,", key, tostring(value)))
        end
    end
    
    return table.concat(lines, "\n")
end

-- 保存优化配置到文件
function HardwareDetector:save_config_to_file(params, file_path)
    local content = self:generate_config_string(params)
    
    local f = io.open(file_path, "w")
    if not f then
        return false, "无法打开配置文件: " .. file_path
    end
    
    f:write(content)
    f:close()
    
    return true, "配置已保存到: " .. file_path
end

-- 打印硬件信息摘要
function HardwareDetector:print_summary()
    local cpu_info = self:get_cpu_info()
    local memory_info = self:get_memory_info()
    local disk_info = self:get_disk_info()
    
    print("\n=== 硬件信息摘要 ===")
    print(string.format("操作系统: %s", self.os_type:upper()))
    print(string.format("CPU: %s (%d 核心)", cpu_info.model, cpu_info.cores))
    print(string.format("频率: %s", cpu_info.frequency))
    print(string.format("内存: %.2f GB 总 / %.2f GB 可用", 
        memory_info.total / (1024*1024*1024), 
        memory_info.available / (1024*1024*1024)))
    print(string.format("磁盘: %.2f GB 总 / %.2f GB 可用", 
        disk_info.total / (1024*1024*1024), 
        disk_info.free / (1024*1024*1024)))
    print(string.format("存储类型: %s", disk_info.is_ssd and "SSD" or "HDD"))
    print("==================\n")
end

return HardwareDetector