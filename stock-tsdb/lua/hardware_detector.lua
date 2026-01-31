-- 硬件信息检测器
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
        
        -- 如果无法通过nproc获取，尝试读取/proc/cpuinfo
        if cpu_info.cores == 0 then
            handle = io.popen("cat /proc/cpuinfo | grep -c 'processor' 2>/dev/null")
            if handle then
                local cores = tonumber(handle:read("*line"))
                handle:close()
                cpu_info.cores = cores or 0
            end
        end
        
        -- 获取CPU型号
        handle = io.popen("cat /proc/cpuinfo | grep -m 1 'model name' | cut -d ':' -f 2 2>/dev/null")
        if handle then
            local model = handle:read("*line")
            handle:close()
            if model then
                cpu_info.model = model:gsub("^%s+", ""):gsub("%s+$", "")
            end
        end
        
        -- 获取CPU频率
        handle = io.popen("cat /proc/cpuinfo | grep -m 1 'cpu MHz' | cut -d ':' -f 2 2>/dev/null")
        if handle then
            local freq = handle:read("*line")
            handle:close()
            if freq then
                cpu_info.frequency = freq:gsub("^%s+", ""):gsub("%s+$", "")
            end
        end
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
        
        -- 估算可用内存
        handle = io.popen("vm_stat | grep 'Pages free:' | awk '{print $3}'")
        if handle then
            local free_pages = tonumber(handle:read("*line"))
            handle:close()
            
            if free_pages then
                handle = io.popen("sysctl -n hw.pagesize")
                if handle then
                    local page_size = tonumber(handle:read("*line"))
                    handle:close()
                    memory_info.available = free_pages * page_size
                end
            end
        end
        
        if memory_info.available == 0 then
            -- 如果无法获取可用内存，使用估算值
            memory_info.available = memory_info.total * 0.7
        end
        
        memory_info.used = memory_info.total - memory_info.available
    else
        -- Linux系统
        local handle = io.popen("cat /proc/meminfo 2>/dev/null")
        if handle then
            local content = handle:read("*all")
            handle:close()
            
            -- 提取总内存
            local total_match = content:match("MemTotal:%s+(%d+)%s+kB")
            if total_match then
                memory_info.total = tonumber(total_match) * 1024
            end
            
            -- 提取可用内存
            local available_match = content:match("MemAvailable:%s+(%d+)%s+kB")
            if available_match then
                memory_info.available = tonumber(available_match) * 1024
            else
                -- 如果没有MemAvailable字段，尝试计算
                local free_match = content:match("MemFree:%s+(%d+)%s+kB")
                local buffers_match = content:match("Buffers:%s+(%d+)%s+kB")
                local cached_match = content:match("Cached:%s+(%d+)%s+kB")
                
                local free = free_match and tonumber(free_match) or 0
                local buffers = buffers_match and tonumber(buffers_match) or 0
                local cached = cached_match and tonumber(cached_match) or 0
                
                memory_info.available = (free + buffers + cached) * 1024
            end
            
            memory_info.used = memory_info.total - memory_info.available
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
    
    if self.os_type == "macos" then
        -- macOS检测SSD
        local handle = io.popen("diskutil info $(df -h / | tail -1 | awk '{print $1}') | grep 'Solid State'")
        if handle then
            local output = handle:read("*all")
            handle:close()
            return output:find("Yes") ~= nil
        end
        return true  -- 默认假设为SSD
    elseif self.os_type == "linux" then
        -- Linux检测SSD
        local handle = io.popen("cat /sys/block/sda/queue/rotational 2>/dev/null || echo 1")
        if handle then
            local rotational = tonumber(handle:read("*line"))
            handle:close()
            return rotational == 0
        end
        return true  -- 默认假设为SSD
    end
    
    -- 默认假设为SSD
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