-- 业务数据Web界面
-- 提供SQL查询和聚合函数支持的Web界面

local BusinessDataWeb = {}
BusinessDataWeb.__index = BusinessDataWeb

-- 导入依赖
local cjson = require "cjson"
local BusinessAggregation = require "business_aggregation"

function BusinessDataWeb:new()
    local obj = setmetatable({}, BusinessDataWeb)
    obj.name = "business_data_web"
    obj.version = "1.0.0"
    obj.description = "业务数据Web界面，支持SQL查询和聚合函数"
    
    -- 初始化聚合引擎
    obj.aggregation_engine = BusinessAggregation:new()
    
    return obj
end

-- 处理SQL查询请求
function BusinessDataWeb:handle_sql_query(request)
    local response = {
        success = false,
        data = nil,
        error = nil,
        execution_time = 0
    }
    
    local start_time = os.clock()
    
    if not request.sql or request.sql == "" then
        response.error = "SQL查询不能为空"
        response.execution_time = os.clock() - start_time
        return response
    end
    
    -- 执行SQL查询
    local result, err = self.aggregation_engine:execute_sql(request.sql)
    
    if result then
        response.success = true
        response.data = result
        response.row_count = #result
    else
        response.error = err or "SQL查询执行失败"
    end
    
    response.execution_time = os.clock() - start_time
    return response
end

-- 获取数据表列表
function BusinessDataWeb:handle_get_tables()
    local response = {
        success = true,
        tables = self.aggregation_engine:get_available_tables()
    }
    return response
end

-- 获取表结构信息
function BusinessDataWeb:handle_get_schema(request)
    local response = {
        success = false,
        schema = nil,
        error = nil
    }
    
    if not request.table_name then
        response.error = "表名不能为空"
        return response
    end
    
    local schema = self.aggregation_engine:get_table_schema(request.table_name)
    
    if schema then
        response.success = true
        response.schema = schema
    else
        response.error = "未知的数据表: " .. request.table_name
    end
    
    return response
end

-- 生成Web界面HTML
function BusinessDataWeb:generate_html()
    return [[
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>业务数据聚合系统 - Stock TSDB</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #2c3e50, #34495e);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header p {
            opacity: 0.9;
            font-size: 1.1em;
        }
        
        .content {
            padding: 30px;
        }
        
        .section {
            margin-bottom: 40px;
            background: #f8f9fa;
            border-radius: 10px;
            padding: 25px;
            border-left: 5px solid #3498db;
        }
        
        .section h2 {
            color: #2c3e50;
            margin-bottom: 20px;
            font-size: 1.5em;
        }
        
        .sql-editor {
            width: 100%;
            min-height: 120px;
            padding: 15px;
            border: 2px solid #e9ecef;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 14px;
            resize: vertical;
            background: #f8f9fa;
        }
        
        .sql-editor:focus {
            outline: none;
            border-color: #3498db;
            background: white;
        }
        
        .btn {
            background: linear-gradient(135deg, #3498db, #2980b9);
            color: white;
            border: none;
            padding: 12px 25px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 600;
            transition: all 0.3s ease;
        }
        
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(52, 152, 219, 0.4);
        }
        
        .btn-secondary {
            background: linear-gradient(135deg, #95a5a6, #7f8c8d);
        }
        
        .btn-success {
            background: linear-gradient(135deg, #27ae60, #229954);
        }
        
        .result-section {
            margin-top: 20px;
        }
        
        .result-table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
            background: white;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        
        .result-table th {
            background: #34495e;
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 600;
        }
        
        .result-table td {
            padding: 12px;
            border-bottom: 1px solid #ecf0f1;
        }
        
        .result-table tr:hover {
            background: #f8f9fa;
        }
        
        .error-message {
            background: #e74c3c;
            color: white;
            padding: 15px;
            border-radius: 8px;
            margin-top: 15px;
        }
        
        .success-message {
            background: #27ae60;
            color: white;
            padding: 15px;
            border-radius: 8px;
            margin-top: 15px;
        }
        
        .info-box {
            background: #d4edda;
            border: 1px solid #c3e6cb;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 20px;
        }
        
        .table-list {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 15px;
            margin-top: 15px;
        }
        
        .table-card {
            background: white;
            border: 1px solid #e9ecef;
            border-radius: 8px;
            padding: 20px;
            transition: all 0.3s ease;
            cursor: pointer;
        }
        
        .table-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        
        .table-card h3 {
            color: #2c3e50;
            margin-bottom: 10px;
        }
        
        .table-card .fields {
            color: #7f8c8d;
            font-size: 0.9em;
        }
        
        .loading {
            text-align: center;
            padding: 20px;
            color: #7f8c8d;
        }
        
        .stats {
            display: flex;
            gap: 15px;
            margin-top: 15px;
        }
        
        .stat-item {
            background: white;
            padding: 15px;
            border-radius: 8px;
            border-left: 4px solid #3498db;
            flex: 1;
        }
        
        .stat-value {
            font-size: 1.5em;
            font-weight: bold;
            color: #2c3e50;
        }
        
        .stat-label {
            font-size: 0.9em;
            color: #7f8c8d;
        }
        
        .code-examples {
            background: #2c3e50;
            color: #ecf0f1;
            padding: 20px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 13px;
            margin-top: 15px;
        }
        
        .example {
            margin-bottom: 10px;
        }
        
        .example .comment {
            color: #95a5a6;
        }
        
        .example .keyword {
            color: #3498db;
        }
        
        .example .function {
            color: #e74c3c;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 业务数据聚合系统</h1>
            <p>Stock TSDB - SQL查询和聚合函数支持</p>
        </div>
        
        <div class="content">
            <!-- 数据表信息 -->
            <div class="section">
                <h2>📋 可用数据表</h2>
                <div id="tables-list" class="loading">加载中...</div>
            </div>
            
            <!-- SQL查询编辑器 -->
            <div class="section">
                <h2>🔍 SQL查询</h2>
                <div class="info-box">
                    <strong>支持功能：</strong> SELECT查询、聚合函数(COUNT, SUM, AVG, MAX, MIN)、GROUP BY分组、WHERE条件过滤
                </div>
                
                <textarea id="sql-editor" class="sql-editor" placeholder="输入SQL查询语句，例如：SELECT COUNT(*) FROM stock_quotes WHERE price > 10"></textarea>
                
                <div style="margin-top: 15px;">
                    <button onclick="executeQuery()" class="btn btn-success">🚀 执行查询</button>
                    <button onclick="clearQuery()" class="btn btn-secondary">🗑️ 清空</button>
                    <button onclick="showExamples()" class="btn">📚 查看示例</button>
                </div>
                
                <div id="query-result" class="result-section"></div>
            </div>
            
            <!-- 查询示例 -->
            <div class="section" id="examples-section" style="display: none;">
                <h2>📚 SQL查询示例</h2>
                <div class="code-examples">
                    <div class="example">
                        <span class="comment">-- 统计股票数据总数</span><br>
                        <span class="keyword">SELECT</span> COUNT(*) <span class="keyword">FROM</span> stock_quotes
                    </div>
                    <div class="example">
                        <span class="comment">-- 计算平均价格</span><br>
                        <span class="keyword">SELECT</span> AVG(price) <span class="keyword">FROM</span> stock_quotes
                    </div>
                    <div class="example">
                        <span class="comment">-- 按股票代码分组统计</span><br>
                        <span class="keyword">SELECT</span> stock_code, COUNT(*), AVG(price) <span class="keyword">FROM</span> stock_quotes <span class="keyword">GROUP BY</span> stock_code
                    </div>
                    <div class="example">
                        <span class="comment">-- 条件查询</span><br>
                        <span class="keyword">SELECT</span> * <span class="keyword">FROM</span> stock_quotes <span class="keyword">WHERE</span> price > 10 <span class="keyword">AND</span> volume > 500000
                    </div>
                    <div class="example">
                        <span class="comment">-- IOT传感器数据统计</span><br>
                        <span class="keyword">SELECT</span> device_id, MAX(value), MIN(value), AVG(value) <span class="keyword">FROM</span> iot_data <span class="keyword">GROUP BY</span> device_id
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        // 页面加载完成后初始化
        document.addEventListener('DOMContentLoaded', function() {
            loadTables();
        });
        
        // 加载数据表列表
        async function loadTables() {
            try {
                const response = await fetch('/business/tables');
                const data = await response.json();
                
                if (data.success) {
                    const tablesList = document.getElementById('tables-list');
                    tablesList.innerHTML = '<div class="table-list">' + 
                        data.tables.map(table => `
                            <div class="table-card" onclick="showTableInfo('${table.name}')">
                                <h3>${table.name}</h3>
                                <div class="fields">字段: ${table.fields.join(', ')}</div>
                                <div style="margin-top: 10px; color: #3498db; font-size: 0.8em;">${table.description}</div>
                            </div>
                        `).join('') + '</div>';
                } else {
                    tablesList.innerHTML = '<div class="error-message">加载失败: ' + data.error + '</div>';
                }
            } catch (error) {
                document.getElementById('tables-list').innerHTML = '<div class="error-message">网络错误: ' + error.message + '</div>';
            }
        }
        
        // 显示表信息
        async function showTableInfo(tableName) {
            const sqlEditor = document.getElementById('sql-editor');
            sqlEditor.value = `SELECT * FROM ${tableName} LIMIT 10`;
        }
        
        // 执行SQL查询
        async function executeQuery() {
            const sql = document.getElementById('sql-editor').value.trim();
            const resultDiv = document.getElementById('query-result');
            
            if (!sql) {
                resultDiv.innerHTML = '<div class="error-message">请输入SQL查询语句</div>';
                return;
            }
            
            resultDiv.innerHTML = '<div class="loading">执行查询中...</div>';
            
            try {
                const response = await fetch('/business/query', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({sql: sql})
                });
                
                const data = await response.json();
                
                if (data.success) {
                    displayQueryResult(data);
                } else {
                    resultDiv.innerHTML = '<div class="error-message">查询失败: ' + data.error + '</div>';
                }
            } catch (error) {
                resultDiv.innerHTML = '<div class="error-message">网络错误: ' + error.message + '</div>';
            }
        }
        
        // 显示查询结果
        function displayQueryResult(data) {
            const resultDiv = document.getElementById('query-result');
            
            if (!data.data || data.data.length === 0) {
                resultDiv.innerHTML = '<div class="success-message">查询成功，但未找到匹配的数据</div>';
                return;
            }
            
            // 获取所有字段名
            const fields = Object.keys(data.data[0]);
            
            let html = `
                <div class="success-message">
                    ✅ 查询成功！找到 ${data.row_count} 条记录，执行时间: ${data.execution_time.toFixed(3)} 秒
                </div>
                <div class="stats">
                    <div class="stat-item">
                        <div class="stat-value">${data.row_count}</div>
                        <div class="stat-label">记录数</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-value">${fields.length}</div>
                        <div class="stat-label">字段数</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-value">${data.execution_time.toFixed(3)}s</div>
                        <div class="stat-label">执行时间</div>
                    </div>
                </div>
                <table class="result-table">
                    <thead>
                        <tr>
                            ${fields.map(field => `<th>${field}</th>`).join('')}
                        </tr>
                    </thead>
                    <tbody>
                        ${data.data.map(row => `
                            <tr>
                                ${fields.map(field => `<td>${formatValue(row[field])}</td>`).join('')}
                            </tr>
                        `).join('')}
                    </tbody>
                </table>
            `;
            
            resultDiv.innerHTML = html;
        }
        
        // 格式化值显示
        function formatValue(value) {
            if (value === null || value === undefined) return '<em>null</em>';
            if (typeof value === 'number') return value.toLocaleString();
            return String(value);
        }
        
        // 清空查询
        function clearQuery() {
            document.getElementById('sql-editor').value = '';
            document.getElementById('query-result').innerHTML = '';
        }
        
        // 显示/隐藏示例
        function showExamples() {
            const examplesSection = document.getElementById('examples-section');
            examplesSection.style.display = examplesSection.style.display === 'none' ? 'block' : 'none';
        }
        
        // 快捷键支持
        document.getElementById('sql-editor').addEventListener('keydown', function(e) {
            if (e.ctrlKey && e.key === 'Enter') {
                executeQuery();
            }
        });
    </script>
</body>
</html>
]]
end

return BusinessDataWeb