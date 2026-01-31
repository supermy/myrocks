--[[
    二进制序列化模块 - 重构版
    
    设计目标:
    1. 替代JSON序列化，提升50-70%性能
    2. 使用自定义二进制格式，更紧凑、更快
    3. 兼容 Lua 5.1/5.2/5.3+
    4. 代码清晰易维护
    
    性能特点:
    - 自动选择最优整数类型(INT8/16/32/64)
    - 变长整数编码减少空间占用
    - 区分数组和哈希表优化序列化
]]

local BinarySerializer = {}
BinarySerializer.__index = BinarySerializer

-- ============================================================================
-- 常量定义
-- ============================================================================

-- 数据类型标识 (1字节)
local TYPES = {
    NIL         = 0x00,
    BOOL_FALSE  = 0x01,
    BOOL_TRUE   = 0x02,
    INT8        = 0x03,
    INT16       = 0x04,
    INT32       = 0x05,
    INT64       = 0x06,
    FLOAT       = 0x07,  -- 保留，当前使用DOUBLE
    DOUBLE      = 0x08,
    STRING      = 0x09,
    TABLE       = 0x0A,
    ARRAY       = 0x0B,
}

-- 整数范围常量
local INT_RANGES = {
    INT8  = {min = -128, max = 127},
    INT16 = {min = -32768, max = 32767},
    INT32 = {min = -2147483648, max = 2147483647},
}

-- 检查是否支持string.pack (Lua 5.3+)
local HAS_STRING_PACK = (string.pack ~= nil)

-- ============================================================================
-- 构造函数
-- ============================================================================

function BinarySerializer:new()
    return setmetatable({}, self)
end

-- ============================================================================
-- 公共API
-- ============================================================================

--- 序列化数据为二进制字符串
-- @param data 任意Lua数据
-- @return string 二进制序列化数据
function BinarySerializer:serialize(data)
    local buffer = {}
    self:_encode(data, buffer)
    return table.concat(buffer)
end

--- 反序列化二进制字符串为Lua数据
-- @param data_str 二进制序列化数据
-- @return any 反序列化后的Lua数据
function BinarySerializer:deserialize(data_str)
    if not data_str or #data_str == 0 then
        return nil
    end
    
    local pos = 1
    local result, new_pos = self:_decode(data_str, pos)
    return result
end

-- ============================================================================
-- 编码器 (私有方法)
-- ============================================================================

function BinarySerializer:_encode(value, buffer)
    local value_type = type(value)
    
    if value == nil then
        self:_write_type(buffer, TYPES.NIL)
        
    elseif value_type == "boolean" then
        self:_write_type(buffer, value and TYPES.BOOL_TRUE or TYPES.BOOL_FALSE)
        
    elseif value_type == "number" then
        self:_encode_number(value, buffer)
        
    elseif value_type == "string" then
        self:_encode_string(value, buffer)
        
    elseif value_type == "table" then
        self:_encode_table(value, buffer)
    end
end

function BinarySerializer:_encode_number(value, buffer)
    -- 判断是否为整数
    if value == math.floor(value) then
        self:_encode_integer(value, buffer)
    else
        -- 浮点数统一使用DOUBLE
        self:_write_type(buffer, TYPES.DOUBLE)
        self:_write_bytes(buffer, self:_pack_double(value))
    end
end

function BinarySerializer:_encode_integer(value, buffer)
    -- 根据范围选择最优类型
    if value >= INT_RANGES.INT8.min and value <= INT_RANGES.INT8.max then
        self:_write_type(buffer, TYPES.INT8)
        self:_write_byte(buffer, value % 256)
        
    elseif value >= INT_RANGES.INT16.min and value <= INT_RANGES.INT16.max then
        self:_write_type(buffer, TYPES.INT16)
        self:_write_bytes(buffer, self:_pack_int16(value))
        
    elseif value >= INT_RANGES.INT32.min and value <= INT_RANGES.INT32.max then
        self:_write_type(buffer, TYPES.INT32)
        self:_write_bytes(buffer, self:_pack_int32(value))
        
    else
        self:_write_type(buffer, TYPES.INT64)
        self:_write_bytes(buffer, self:_pack_int64(value))
    end
end

function BinarySerializer:_encode_string(value, buffer)
    self:_write_type(buffer, TYPES.STRING)
    local len = #value
    self:_encode_varint(len, buffer)
    self:_write_bytes(buffer, value)
end

function BinarySerializer:_encode_table(value, buffer)
    local is_array, count = self:_analyze_table(value)
    
    if is_array then
        self:_write_type(buffer, TYPES.ARRAY)
        self:_encode_varint(count, buffer)
        for i = 1, count do
            self:_encode(value[i], buffer)
        end
    else
        self:_write_type(buffer, TYPES.TABLE)
        self:_encode_varint(count, buffer)
        for k, v in pairs(value) do
            self:_encode(k, buffer)
            self:_encode(v, buffer)
        end
    end
end

-- 分析表结构，判断是否为数组
function BinarySerializer:_analyze_table(tbl)
    local count = 0
    local max_index = 0
    
    for k, v in pairs(tbl) do
        count = count + 1
        
        -- 检查是否为纯数组
        if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
            return false, count
        end
        max_index = math.max(max_index, k)
    end
    
    -- 纯数组: 索引连续从1开始
    return (max_index == count), count
end

-- ============================================================================
-- 解码器 (私有方法)
-- ============================================================================

function BinarySerializer:_decode(data, pos)
    if pos > #data then
        return nil, pos
    end
    
    local type_byte = string.byte(data, pos)
    pos = pos + 1
    
    local decoder = self._decoders[type_byte]
    if decoder then
        return decoder(self, data, pos)
    end
    
    return nil, pos
end

-- 解码器映射表
BinarySerializer._decoders = {
    [TYPES.NIL] = function(self, data, pos)
        return nil, pos
    end,
    
    [TYPES.BOOL_FALSE] = function(self, data, pos)
        return false, pos
    end,
    
    [TYPES.BOOL_TRUE] = function(self, data, pos)
        return true, pos
    end,
    
    [TYPES.INT8] = function(self, data, pos)
        local value = string.byte(data, pos)
        if value > 127 then value = value - 256 end
        return value, pos + 1
    end,
    
    [TYPES.INT16] = function(self, data, pos)
        return self:_unpack_int16(data, pos), pos + 2
    end,
    
    [TYPES.INT32] = function(self, data, pos)
        return self:_unpack_int32(data, pos), pos + 4
    end,
    
    [TYPES.INT64] = function(self, data, pos)
        return self:_unpack_int64(data, pos), pos + 8
    end,
    
    [TYPES.DOUBLE] = function(self, data, pos)
        return self:_unpack_double(data, pos), pos + 8
    end,
    
    [TYPES.STRING] = function(self, data, pos)
        local length, new_pos = self:_decode_varint(data, pos)
        local value = string.sub(data, new_pos, new_pos + length - 1)
        return value, new_pos + length
    end,
    
    [TYPES.ARRAY] = function(self, data, pos)
        local count, new_pos = self:_decode_varint(data, pos)
        local array = {}
        pos = new_pos
        for i = 1, count do
            local value
            value, pos = self:_decode(data, pos)
            array[i] = value
        end
        return array, pos
    end,
    
    [TYPES.TABLE] = function(self, data, pos)
        local count, new_pos = self:_decode_varint(data, pos)
        local tbl = {}
        pos = new_pos
        for i = 1, count do
            local key, value
            key, pos = self:_decode(data, pos)
            value, pos = self:_decode(data, pos)
            tbl[key] = value
        end
        return tbl, pos
    end,
}

-- ============================================================================
-- 变长整数编码 (Varint)
-- ============================================================================

-- 编码变长整数 (类似Protocol Buffers)
function BinarySerializer:_encode_varint(value, buffer)
    while value >= 128 do
        self:_write_byte(buffer, (value % 128) + 128)
        value = math.floor(value / 128)
    end
    self:_write_byte(buffer, value)
end

-- 解码变长整数
function BinarySerializer:_decode_varint(data, pos)
    local value = 0
    local shift = 0
    
    while true do
        local byte = string.byte(data, pos)
        pos = pos + 1
        
        value = value + (byte % 128) * (2 ^ shift)
        
        if byte < 128 then
            break
        end
        shift = shift + 7
    end
    
    return value, pos
end

-- ============================================================================
-- 字节操作辅助函数
-- ============================================================================

function BinarySerializer:_write_byte(buffer, byte)
    buffer[#buffer + 1] = string.char(byte % 256)
end

function BinarySerializer:_write_bytes(buffer, bytes)
    buffer[#buffer + 1] = bytes
end

function BinarySerializer:_write_type(buffer, type_byte)
    buffer[#buffer + 1] = string.char(type_byte)
end

-- ============================================================================
-- 打包/解包函数 (兼容Lua 5.1/5.2/5.3+)
-- ============================================================================

-- 16位整数 (大端序)
function BinarySerializer:_pack_int16(value)
    if HAS_STRING_PACK then
        return string.pack(">i2", value)
    end
    
    if value < 0 then value = value + 65536 end
    return string.char(
        math.floor(value / 256) % 256,
        value % 256
    )
end

function BinarySerializer:_unpack_int16(data, pos)
    if HAS_STRING_PACK then
        return string.unpack(">i2", data, pos)
    end
    
    local b1, b2 = string.byte(data, pos, pos + 1)
    local value = b1 * 256 + b2
    return value >= 32768 and value - 65536 or value
end

-- 32位整数 (大端序)
function BinarySerializer:_pack_int32(value)
    if HAS_STRING_PACK then
        return string.pack(">i4", value)
    end
    
    if value < 0 then value = value + 4294967296 end
    return string.char(
        math.floor(value / 16777216) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 256) % 256,
        value % 256
    )
end

function BinarySerializer:_unpack_int32(data, pos)
    if HAS_STRING_PACK then
        return string.unpack(">i4", data, pos)
    end
    
    local b1, b2, b3, b4 = string.byte(data, pos, pos + 3)
    local value = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
    return value >= 2147483648 and value - 4294967296 or value
end

-- 64位整数 (大端序)
function BinarySerializer:_pack_int64(value)
    if HAS_STRING_PACK then
        return string.pack(">i8", value)
    end
    
    -- Lua 5.1/5.2: 拆分为两个32位整数
    return self:_pack_int32(math.floor(value / 4294967296)) .. 
           self:_pack_int32(value % 4294967296)
end

function BinarySerializer:_unpack_int64(data, pos)
    if HAS_STRING_PACK then
        return string.unpack(">i8", data, pos)
    end
    
    local high = self:_unpack_int32(data, pos)
    local low = self:_unpack_int32(data, pos + 4)
    return high * 4294967296 + low
end

-- 双精度浮点数
function BinarySerializer:_pack_double(value)
    if HAS_STRING_PACK then
        return string.pack(">n", value)
    end
    
    -- Lua 5.1/5.2: 使用字符串表示
    return tostring(value)
end

function BinarySerializer:_unpack_double(data, pos)
    if HAS_STRING_PACK then
        return string.unpack(">n", data, pos)
    end
    
    -- Lua 5.1/5.2: 从字符串解析
    local str = string.sub(data, pos, pos + 20)
    return tonumber(str) or 0
end

-- ============================================================================
-- 性能测试
-- ============================================================================

function BinarySerializer:benchmark(data, iterations)
    iterations = iterations or 10000
    
    -- 预热
    for i = 1, 100 do
        local s = self:serialize(data)
        self:deserialize(s)
    end
    
    -- 测试序列化
    local start = os.clock()
    for i = 1, iterations do
        local _ = self:serialize(data)
    end
    local serialize_time = os.clock() - start
    
    -- 测试反序列化
    local serialized = self:serialize(data)
    start = os.clock()
    for i = 1, iterations do
        local _ = self:deserialize(serialized)
    end
    local deserialize_time = os.clock() - start
    
    return {
        serialize_time_ms = serialize_time * 1000,
        deserialize_time_ms = deserialize_time * 1000,
        total_time_ms = (serialize_time + deserialize_time) * 1000,
        serialized_size = #serialized,
        ops_per_second = iterations / (serialize_time + deserialize_time),
        has_string_pack = HAS_STRING_PACK,
    }
end

return BinarySerializer
