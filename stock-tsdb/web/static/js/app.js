// Stock-TSDB 元数据管理前端应用

class MetadataManager {
    constructor() {
        this.apiBase = window.location.origin;
        this.currentSection = 'dashboard';
        this.configData = null;
        this.metadata = null;
        this.stats = null;
        
        // 分页相关变量
        this.currentPage = 1;
        this.pageSize = 10;
        this.totalItems = 0;
        this.totalPages = 1;
        
        this.init();
    }
    
    init() {
        this.bindEvents();
        this.loadDashboard();
        this.showNotification('系统初始化完成', 'success');
    }
    
    bindEvents() {
        // 导航菜单点击事件
        document.querySelectorAll('nav a').forEach(link => {
            link.addEventListener('click', (e) => {
                e.preventDefault();
                const target = e.target.getAttribute('href').substring(1);
                this.switchSection(target);
            });
        });
        
        // 配置标签页切换
        document.addEventListener('click', (e) => {
            if (e.target.classList.contains('config-tab')) {
                this.switchConfigTab(e.target.dataset.tab);
            }
        });
        
        // 配置表单提交
        document.addEventListener('submit', (e) => {
            if (e.target.classList.contains('config-form')) {
                e.preventDefault();
                this.saveConfig(e.target);
            }
        });
    }
    
    switchSection(section) {
        // 更新导航激活状态
        document.querySelectorAll('nav a').forEach(link => {
            link.classList.remove('active');
        });
        document.querySelector(`nav a[href="#${section}"]`).classList.add('active');
        
        // 切换内容区域
        document.querySelectorAll('main section').forEach(sectionEl => {
            sectionEl.style.display = 'none';
        });
        document.getElementById(section).style.display = 'block';
        
        this.currentSection = section;
        
        // 加载对应数据
        switch(section) {
            case 'dashboard':
                this.loadDashboard();
                break;
            case 'config':
                this.loadConfigManager();
                break;
            case 'metadata':
                this.loadMetadataViewer();
                break;
            case 'cluster':
                this.loadClusterStatus();
                break;
            case 'business':
                this.loadBusinessManager();
                break;
        }
    }
    
    async apiCall(endpoint, options = {}) {
        try {
            const response = await fetch(`${this.apiBase}/api${endpoint}`, {
                headers: {
                    'Content-Type': 'application/json',
                    ...options.headers
                },
                ...options
            });
            
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            
            return await response.json();
        } catch (error) {
            console.error('API调用失败:', error);
            this.showNotification(`API调用失败: ${error.message}`, 'error');
            throw error;
        }
    }
    
    async loadDashboard() {
        try {
            // 加载统计数据
            this.stats = await this.apiCall('/stats');
            this.metadata = await this.apiCall('/metadata');
            
            // 更新统计卡片
            this.updateStatCard('config-count', this.metadata.config_count || 0);
            this.updateStatCard('business-count', this.metadata.business_types ? this.metadata.business_types.length : 0);
            this.updateStatCard('cluster-nodes', '加载中...');
            this.updateStatCard('total-points', this.stats.storage.total_points || 0);
            
            // 加载集群信息
            const clusterInfo = await this.apiCall('/cluster');
            this.updateStatCard('cluster-nodes', clusterInfo.nodes ? clusterInfo.nodes.length : 0);
            
        } catch (error) {
            console.error('加载仪表板数据失败:', error);
        }
    }
    
    async loadConfigManager() {
        try {
            this.configData = await this.apiCall('/config');
            this.renderConfigManager();
        } catch (error) {
            console.error('加载配置数据失败:', error);
        }
    }
    
    renderConfigManager() {
        const container = document.getElementById('config-editor');
        
        if (!this.configData) {
            container.innerHTML = '<div class="loading"><div class="spinner"></div>加载配置数据...</div>';
            return;
        }
        
        container.innerHTML = `
            <div class="config-editor">
                <div class="config-tabs">
                    <button class="config-tab active" data-tab="business">业务配置</button>
                    <button class="config-tab" data-tab="system">系统配置</button>
                    <button class="config-tab" data-tab="instance">实例配置</button>
                </div>
                
                <div class="config-content active" data-tab="business">
                    ${this.renderBusinessConfigs()}
                </div>
                
                <div class="config-content" data-tab="system">
                    ${this.renderSystemConfig()}
                </div>
                
                <div class="config-content" data-tab="instance">
                    ${this.renderInstanceConfigs()}
                </div>
            </div>
        `;
    }
    
    renderBusinessConfigs() {
        if (!this.configData.business_configs) {
            return '<p>暂无业务配置</p>';
        }
        
        let html = '<div class="business-configs">';
        
        for (const [bizType, config] of Object.entries(this.configData.business_configs)) {
            html += `
                <div class="business-config">
                    <h3>${config.name || bizType}</h3>
                    <p class="config-description">${config.description || '暂无描述'}</p>
                    
                    <form class="config-form" data-key="business:${bizType}">
                        <div class="form-group">
                            <label>业务名称</label>
                            <input type="text" name="name" value="${config.name || ''}" required>
                        </div>
                        
                        <div class="form-group">
                            <label>描述</label>
                            <textarea name="description" rows="3">${config.description || ''}</textarea>
                        </div>
                        
                        <div class="form-group">
                            <label>块大小(秒)</label>
                            <input type="number" name="block_size" value="${config.block_size || 60}" min="1">
                        </div>
                        
                        <div class="form-group">
                            <label>保留天数</label>
                            <input type="number" name="retention_days" value="${config.retention_days || 30}" min="1">
                        </div>
                        
                        <div class="form-group">
                            <label>压缩算法</label>
                            <select name="compression">
                                <option value="lz4" ${config.compression === 'lz4' ? 'selected' : ''}>LZ4</option>
                                <option value="snappy" ${config.compression === 'snappy' ? 'selected' : ''}>Snappy</option>
                                <option value="none" ${!config.compression ? 'selected' : ''}>无压缩</option>
                            </select>
                        </div>
                        
                        <button type="submit" class="btn btn-primary">保存配置</button>
                    </form>
                </div>
            `;
        }
        
        html += '</div>';
        return html;
    }
    
    renderSystemConfig() {
        if (!this.configData.system_config) {
            return '<p>暂无系统配置</p>';
        }
        
        const config = this.configData.system_config;
        
        return `
            <form class="config-form" data-key="system:main">
                <h4>服务器配置</h4>
                <div class="form-group">
                    <label>端口</label>
                    <input type="number" name="server.port" value="${config.server?.port || 6379}" min="1" max="65535">
                </div>
                
                <div class="form-group">
                    <label>绑定地址</label>
                    <input type="text" name="server.bind" value="${config.server?.bind || '0.0.0.0'}">
                </div>
                
                <div class="form-group">
                    <label>最大连接数</label>
                    <input type="number" name="server.max_connections" value="${config.server?.max_connections || 10000}" min="1">
                </div>
                
                <h4>存储配置</h4>
                <div class="form-group">
                    <label>数据目录</label>
                    <input type="text" name="storage.data_dir" value="${config.storage?.data_dir || './data'}">
                </div>
                
                <div class="form-group">
                    <label>写缓冲区大小(MB)</label>
                    <input type="number" name="storage.write_buffer_size" value="${(config.storage?.write_buffer_size || 67108864) / 1024 / 1024}" min="1">
                </div>
                
                <button type="submit" class="btn btn-primary">保存系统配置</button>
            </form>
        `;
    }
    
    renderInstanceConfigs() {
        if (!this.configData.instance_configs || Object.keys(this.configData.instance_configs).length === 0) {
            return '<p>暂无实例配置</p>';
        }
        
        let html = '<div class="instance-configs">';
        
        for (const [instanceId, config] of Object.entries(this.configData.instance_configs)) {
            html += `
                <div class="instance-config">
                    <h4>实例: ${instanceId}</h4>
                    <form class="config-form" data-key="instance:${instanceId}">
                        <div class="form-group">
                            <label>实例名称</label>
                            <input type="text" name="name" value="${config.name || instanceId}">
                        </div>
                        
                        <div class="form-group">
                            <label>业务类型</label>
                            <input type="text" name="business_type" value="${config.business_type || ''}">
                        </div>
                        
                        <div class="form-group">
                            <label>节点ID</label>
                            <input type="text" name="node_id" value="${config.node_id || ''}">
                        </div>
                        
                        <button type="submit" class="btn btn-primary">保存实例配置</button>
                        <button type="button" class="btn btn-danger" onclick="metadataManager.deleteInstance('${instanceId}')">删除实例</button>
                    </form>
                </div>
            `;
        }
        
        html += '</div>';
        return html;
    }
    
    switchConfigTab(tab) {
        // 更新标签页激活状态
        document.querySelectorAll('.config-tab').forEach(tabEl => {
            tabEl.classList.remove('active');
        });
        document.querySelector(`.config-tab[data-tab="${tab}"]`).classList.add('active');
        
        // 切换内容区域
        document.querySelectorAll('.config-content').forEach(content => {
            content.classList.remove('active');
        });
        document.querySelector(`.config-content[data-tab="${tab}"]`).classList.add('active');
    }
    
    async saveConfig(form) {
        const formData = new FormData(form);
        const configKey = form.dataset.key;
        const configValue = {};
        
        // 将表单数据转换为配置对象
        for (const [key, value] of formData.entries()) {
            if (value.trim() !== '') {
                // 处理嵌套属性（如 server.port）
                const keys = key.split('.');
                let current = configValue;
                
                for (let i = 0; i < keys.length - 1; i++) {
                    if (!current[keys[i]]) {
                        current[keys[i]] = {};
                    }
                    current = current[keys[i]];
                }
                
                // 转换数值类型
                current[keys[keys.length - 1]] = isNaN(value) ? value : Number(value);
            }
        }
        
        try {
            await this.apiCall('/config/update', {
                method: 'POST',
                body: JSON.stringify({
                    key: configKey,
                    value: configValue
                })
            });
            
            this.showNotification('配置保存成功', 'success');
            this.loadConfigManager(); // 重新加载配置
        } catch (error) {
            console.error('保存配置失败:', error);
        }
    }
    
    async deleteInstance(instanceId) {
        if (!confirm(`确定要删除实例 "${instanceId}" 吗？此操作不可撤销。`)) {
            return;
        }
        
        try {
            await this.apiCall('/config/update', {
                method: 'POST',
                body: JSON.stringify({
                    key: `instance:${instanceId}`,
                    value: null // 设置为null表示删除
                })
            });
            
            this.showNotification('实例删除成功', 'success');
            this.loadConfigManager();
        } catch (error) {
            console.error('删除实例失败:', error);
        }
    }
    
    async loadMetadataViewer() {
        try {
            this.metadata = await this.apiCall('/metadata');
            this.renderMetadataViewer();
        } catch (error) {
            console.error('加载元数据失败:', error);
        }
    }
    
    renderMetadataViewer() {
        const container = document.getElementById('metadata-viewer');
        
        if (!this.metadata) {
            container.innerHTML = '<div class="loading"><div class="spinner"></div>加载元数据...</div>';
            return;
        }
        
        container.innerHTML = `
            <div class="metadata-viewer">
                <div class="metadata-summary">
                    <h3>元数据概览</h3>
                    <p>配置项总数: <strong>${this.metadata.config_count || 0}</strong></p>
                    <p>业务类型数量: <strong>${this.metadata.business_types ? this.metadata.business_types.length : 0}</strong></p>
                </div>
                
                <div class="business-types">
                    <h3>业务类型列表</h3>
                    ${this.renderBusinessTypesTable()}
                </div>
                
                <div class="raw-data">
                    <h3>原始数据</h3>
                    <div class="json-viewer">
                        <pre>${JSON.stringify(this.metadata, null, 2)}</pre>
                    </div>
                </div>
            </div>
        `;
    }
    
    renderBusinessTypesTable() {
        if (!this.metadata.business_types || this.metadata.business_types.length === 0) {
            return '<p>暂无业务类型数据</p>';
        }
        
        let html = '<table class="data-table">';
        html += '<thead><tr><th>类型</th><th>名称</th><th>描述</th></tr></thead>';
        html += '<tbody>';
        
        this.metadata.business_types.forEach((bizType, index) => {
            // 为每个业务类型生成一个简单的类型标识
            const typeId = 'biz_type_' + (index + 1);
            // 使用业务类型名称作为显示名称
            const displayName = bizType;
            // 生成简单的描述
            const description = `这是${bizType}业务类型的数据处理模块`;
            
            html += `<tr>
                <td><code>${typeId}</code></td>
                <td>${displayName}</td>
                <td>${description}</td>
            </tr>`;
        });
        
        html += '</tbody></table>';
        return html;
    }
    
    async loadClusterStatus() {
        try {
            const clusterInfo = await this.apiCall('/cluster');
            this.renderClusterStatus(clusterInfo);
        } catch (error) {
            console.error('加载集群状态失败:', error);
        }
    }
    
    renderClusterStatus(clusterInfo) {
        const container = document.getElementById('cluster-status');
        
        container.innerHTML = `
            <div class="cluster-status">
                <div class="cluster-summary">
                    <h3>集群概览</h3>
                    <p>集群状态: <span class="status-indicator ${clusterInfo.status === 'online' ? 'status-online' : 'status-offline'}"></span> ${clusterInfo.status || 'unknown'}</p>
                    <p>主节点: ${clusterInfo.leader || '无'}</p>
                    <p>节点数量: ${clusterInfo.nodes ? clusterInfo.nodes.length : 0}</p>
                </div>
                
                <div class="nodes-list">
                    <h3>节点列表</h3>
                    ${this.renderNodesTable(clusterInfo.nodes || [])}
                </div>
            </div>
        `;
    }
    
    renderNodesTable(nodes) {
        if (nodes.length === 0) {
            return '<p>暂无节点数据</p>';
        }
        
        let html = '<table class="data-table">';
        html += '<thead><tr><th>节点ID</th><th>地址</th><th>状态</th><th>最后活跃</th></tr></thead>';
        html += '<tbody>';
        
        nodes.forEach(node => {
            html += `<tr>
                <td>${node.id || '未知'}</td>
                <td>${node.address || '未知'}</td>
                <td><span class="status-indicator ${node.status === 'online' ? 'status-online' : 'status-offline'}"></span> ${node.status || 'unknown'}</td>
                <td>${node.last_active ? new Date(node.last_active).toLocaleString() : '未知'}</td>
            </tr>`;
        });
        
        html += '</tbody></table>';
        return html;
    }
    
    async loadBusinessManager() {
        try {
            const businessInfo = await this.apiCall('/business');
            this.renderBusinessManager(businessInfo);
        } catch (error) {
            console.error('加载业务信息失败:', error);
        }
    }
    
    renderBusinessManager(businessInfo) {
        const container = document.getElementById('business-manager');
        
        container.innerHTML = `
            <div class="business-manager">
                <div class="business-summary">
                    <h3>业务管理</h3>
                    <p>实例数量: ${businessInfo.instances ? Object.keys(businessInfo.instances).length : 0}</p>
                    <p>插件数量: ${businessInfo.plugins ? businessInfo.plugins.length : 0}</p>
                </div>
                
                <div class="business-tabs">
                    <button class="business-tab active" data-tab="overview">概览</button>
                    <button class="business-tab" data-tab="instances">实例管理</button>
                    <button class="business-tab" data-tab="data-viewer">数据查看</button>
                    <button class="business-tab" data-tab="plugins">插件管理</button>
                </div>
                
                <div class="business-content active" data-tab="overview">
                    <div class="performance-metrics">
                        <h3>性能指标</h3>
                        <div class="stats-grid">
                            <div class="stat-card">
                                <h3>写入速率</h3>
                                <div class="stat-value">${businessInfo.performance?.write_rate || 0}/秒</div>
                            </div>
                            <div class="stat-card">
                                <h3>查询速率</h3>
                                <div class="stat-value">${businessInfo.performance?.query_rate || 0}/秒</div>
                            </div>
                            <div class="stat-card">
                                <h3>缓存命中率</h3>
                                <div class="stat-value">${businessInfo.performance?.cache_hit_rate || 0}%</div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="pagination-controls">
                        <button class="btn btn-secondary" id="prev-page">上一页</button>
                        <span class="page-info">第 <span id="current-page">1</span> 页，共 <span id="total-pages">1</span> 页</span>
                        <button class="btn btn-secondary" id="next-page">下一页</button>
                        <select id="page-size">
                            <option value="10">10 条/页</option>
                            <option value="20">20 条/页</option>
                            <option value="50">50 条/页</option>
                        </select>
                    </div>
                </div>
                
                <div class="business-content" data-tab="instances">
                    <div class="instances-list">
                        <h3>实例列表</h3>
                        <div class="instance-actions">
                            <button id="create-instance" class="btn btn-primary">创建新实例</button>
                            <button id="refresh-instances" class="btn btn-secondary">刷新列表</button>
                        </div>
                        <div id="instances-table">
                            <!-- 实例列表将通过分页功能动态加载 -->
                        </div>
                        <div class="pagination-controls">
                            <button class="btn btn-secondary" id="prev-page">上一页</button>
                            <span class="page-info">第 <span id="current-page">1</span> 页，共 <span id="total-pages">1</span> 页</span>
                            <button class="btn btn-secondary" id="next-page">下一页</button>
                            <select id="page-size">
                                <option value="10">10 条/页</option>
                                <option value="20">20 条/页</option>
                                <option value="50">50 条/页</option>
                            </select>
                        </div>
                    </div>
                </div>
                
                <div class="business-content" data-tab="data-viewer">
                    <div class="data-viewer">
                        <h3>数据查看器</h3>
                        <div class="data-filter">
                            <input type="text" id="data-search" placeholder="搜索数据..." class="search-input">
                            <select id="data-type-filter">
                                <option value="">所有类型</option>
                                <option value="stock">股票数据</option>
                                <option value="market">市场数据</option>
                                <option value="trade">交易数据</option>
                            </select>
                            <button id="apply-filter" class="btn btn-primary">应用筛选</button>
                            <button id="reset-filter" class="btn btn-secondary">重置</button>
                        </div>
                        <div id="data-table">
                            <!-- 数据表格将通过分页功能动态加载 -->
                        </div>
                        <div class="pagination-controls">
                            <button class="btn btn-secondary" id="prev-page">上一页</button>
                            <span class="page-info">第 <span id="current-page">1</span> 页，共 <span id="total-pages">1</span> 页</span>
                            <button class="btn btn-secondary" id="next-page">下一页</button>
                            <select id="page-size">
                                <option value="10">10 条/页</option>
                                <option value="20">20 条/页</option>
                                <option value="50">50 条/页</option>
                            </select>
                        </div>
                    </div>
                </div>
                
                <div class="business-content" data-tab="plugins">
                    <div class="plugins-manager">
                        <h3>插件管理</h3>
                        <div id="plugins-list">
                            <!-- 插件列表将通过分页功能动态加载 -->
                        </div>
                        <div class="pagination-controls">
                            <button class="btn btn-secondary" id="prev-page">上一页</button>
                            <span class="page-info">第 <span id="current-page">1</span> 页，共 <span id="total-pages">1</span> 页</span>
                            <button class="btn btn-secondary" id="next-page">下一页</button>
                            <select id="page-size">
                                <option value="10">10 条/页</option>
                                <option value="20">20 条/页</option>
                                <option value="50">50 条/页</option>
                            </select>
                        </div>
                    </div>
                </div>
            </div>
        `;
        
        // 绑定分页事件
        this.bindPaginationEvents();
        
        // 绑定标签页切换事件
        this.bindBusinessTabEvents();
        
        // 绑定数据筛选事件
        this.bindDataFilterEvents();
        
        // 绑定实例操作事件
        this.bindInstanceActions();
        
        // 初始化分页数据
        this.initPagination();
    }
    
    bindPaginationEvents() {
        const prevPageEl = document.getElementById('prev-page');
        const nextPageEl = document.getElementById('next-page');
        const pageSizeEl = document.getElementById('page-size');
        
        // 安全地绑定分页事件，如果元素不存在则跳过
        if (prevPageEl) {
            prevPageEl.addEventListener('click', () => this.previousPage());
        }
        if (nextPageEl) {
            nextPageEl.addEventListener('click', () => this.nextPage());
        }
        if (pageSizeEl) {
            pageSizeEl.addEventListener('change', (e) => this.changePageSize(e.target.value));
        }
    }
    
    bindBusinessTabEvents() {
        document.querySelectorAll('.business-tab').forEach(tab => {
            tab.addEventListener('click', (e) => {
                e.preventDefault();
                this.switchBusinessTab(e.target.dataset.tab);
            });
        });
    }
    
    switchBusinessTab(tab) {
        // 更新标签页激活状态
        document.querySelectorAll('.business-tab').forEach(tabEl => {
            tabEl.classList.remove('active');
        });
        document.querySelector(`.business-tab[data-tab="${tab}"]`).classList.add('active');
        
        // 切换内容区域
        document.querySelectorAll('.business-content').forEach(content => {
            content.classList.remove('active');
        });
        document.querySelector(`.business-content[data-tab="${tab}"]`).classList.add('active');
        
        // 重置分页并加载数据
        this.currentPage = 1;
        this.loadPageData();
    }
    
    bindDataFilterEvents() {
        const applyFilterBtn = document.getElementById('apply-filter');
        const resetFilterBtn = document.getElementById('reset-filter');
        const searchInput = document.getElementById('data-search');
        
        if (applyFilterBtn) {
            applyFilterBtn.addEventListener('click', () => {
                this.currentPage = 1;
                this.loadPageData();
            });
        }
        
        if (resetFilterBtn) {
            resetFilterBtn.addEventListener('click', () => {
                if (searchInput) searchInput.value = '';
                const typeFilter = document.getElementById('data-type-filter');
                if (typeFilter) typeFilter.value = '';
                this.currentPage = 1;
                this.loadPageData();
            });
        }
        
        if (searchInput) {
            searchInput.addEventListener('keypress', (e) => {
                if (e.key === 'Enter') {
                    this.currentPage = 1;
                    this.loadPageData();
                }
            });
        }
    }
    
    bindInstanceActions() {
        const createBtn = document.getElementById('create-instance');
        const refreshBtn = document.getElementById('refresh-instances');
        
        if (createBtn) {
            createBtn.addEventListener('click', () => this.createInstance());
        }
        
        if (refreshBtn) {
            refreshBtn.addEventListener('click', () => {
                this.currentPage = 1;
                this.loadPageData();
            });
        }
    }
    
    async createInstance() {
        const instanceId = prompt('请输入新实例ID:');
        if (!instanceId) return;
        
        const businessType = prompt('请输入业务类型:');
        if (!businessType) return;
        
        try {
            await this.apiCall('/business/instance/create', {
                method: 'POST',
                body: JSON.stringify({
                    instance_id: instanceId,
                    business_type: businessType
                })
            });
            
            this.showNotification('实例创建成功', 'success');
            this.currentPage = 1;
            this.loadPageData();
        } catch (error) {
            console.error('创建实例失败:', error);
            this.showNotification('创建实例失败', 'error');
        }
    }
    
    async toggleInstance(instanceId, isOnline) {
        const action = isOnline ? 'stop' : 'start';
        
        try {
            await this.apiCall(`/business/instance/${action}`, {
                method: 'POST',
                body: JSON.stringify({ instance_id: instanceId })
            });
            
            this.showNotification(`实例${isOnline ? '停止' : '启动'}成功`, 'success');
            this.loadPageData();
        } catch (error) {
            console.error('操作实例失败:', error);
            this.showNotification('操作实例失败', 'error');
        }
    }
    
    async deleteInstance(instanceId) {
        if (!confirm(`确定要删除实例 "${instanceId}" 吗？此操作不可撤销。`)) {
            return;
        }
        
        try {
            await this.apiCall('/business/instance/delete', {
                method: 'POST',
                body: JSON.stringify({ instance_id: instanceId })
            });
            
            this.showNotification('实例删除成功', 'success');
            this.loadPageData();
        } catch (error) {
            console.error('删除实例失败:', error);
            this.showNotification('删除实例失败', 'error');
        }
    }
    
    initPagination() {
        // 分页变量已在构造函数中定义，这里只需要重置状态
        this.currentPage = 1;
        this.updatePaginationUI();
    }
    
    previousPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.loadPageData();
        }
    }
    
    nextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.loadPageData();
        }
    }
    
    changePageSize(size) {
        this.pageSize = parseInt(size);
        this.currentPage = 1;
        this.calculateTotalPages();
        this.loadPageData();
    }
    
    calculateTotalPages() {
        this.totalPages = Math.ceil(this.totalItems / this.pageSize);
        if (this.totalPages === 0) this.totalPages = 1;
    }
    
    updatePaginationUI() {
        const currentPageEl = document.getElementById('current-page');
        const totalPagesEl = document.getElementById('total-pages');
        const prevPageEl = document.getElementById('prev-page');
        const nextPageEl = document.getElementById('next-page');
        const pageSizeEl = document.getElementById('page-size');
        
        // 安全地更新分页UI，如果元素不存在则跳过
        if (currentPageEl) currentPageEl.textContent = this.currentPage;
        if (totalPagesEl) totalPagesEl.textContent = this.totalPages;
        if (prevPageEl) prevPageEl.disabled = this.currentPage === 1;
        if (nextPageEl) nextPageEl.disabled = this.currentPage === this.totalPages;
        if (pageSizeEl) pageSizeEl.value = this.pageSize;
    }
    
    async loadPageData() {
        // 根据当前标签页加载不同类型的数据
        const activeTab = document.querySelector('.business-content.active').dataset.tab;
        
        try {
            switch(activeTab) {
                case 'instances':
                    await this.loadInstancesPage();
                    break;
                case 'data-viewer':
                    await this.loadDataViewerPage();
                    break;
                case 'plugins':
                    await this.loadPluginsPage();
                    break;
                default:
                    // 概览页不需要分页
                    break;
            }
            this.updatePaginationUI();
        } catch (error) {
            console.error('加载分页数据失败:', error);
            this.showNotification('加载数据失败', 'error');
        }
    }
    
    async loadInstancesPage() {
        const businessInfo = await this.apiCall('/business');
        const instances = businessInfo.instances ? Object.entries(businessInfo.instances) : [];
        this.totalItems = instances.length;
        this.calculateTotalPages();
        
        const startIndex = (this.currentPage - 1) * this.pageSize;
        const endIndex = Math.min(startIndex + this.pageSize, this.totalItems);
        const pageInstances = instances.slice(startIndex, endIndex);
        
        let html = '<table class="data-table"><thead><tr><th>实例ID</th><th>业务类型</th><th>状态</th><th>最后更新</th><th>数据点数</th><th>操作</th></tr></thead><tbody>';
        
        pageInstances.forEach(([instanceId, instance]) => {
            const isOnline = instance.status === 'running';
            html += `<tr>
                <td>${instanceId}</td>
                <td>${instance.type || '未知'}</td>
                <td><span class="status-indicator ${isOnline ? 'status-online' : 'status-offline'}"></span> ${instance.status || 'unknown'}</td>
                <td>${instance.last_update ? new Date(instance.last_update * 1000).toLocaleString() : '未知'}</td>
                <td>${instance.data_points || 0}</td>
                <td class="instance-actions">
                    <button class="btn btn-small ${isOnline ? 'btn-warning' : 'btn-success'}" onclick="metadataManager.toggleInstance('${instanceId}', ${isOnline})">
                        ${isOnline ? '停止' : '启动'}
                    </button>
                    <button class="btn btn-small btn-danger" onclick="metadataManager.deleteInstance('${instanceId}')">删除</button>
                </td>
            </tr>`;
        });
        
        html += '</tbody></table>';
        document.getElementById('instances-table').innerHTML = html;
    }
    
    async loadDataViewerPage() {
        // 获取筛选条件
        const searchTerm = document.getElementById('data-search')?.value || '';
        const typeFilter = document.getElementById('data-type-filter')?.value || '';
        
        // 模拟数据查看器的分页加载
        const mockData = await this.apiCall('/business/data');
        let filteredData = mockData.items || [];
        
        // 应用筛选条件
        if (searchTerm) {
            filteredData = filteredData.filter(item => 
                JSON.stringify(item).toLowerCase().includes(searchTerm.toLowerCase())
            );
        }
        
        if (typeFilter) {
            filteredData = filteredData.filter(item => 
                item.tags && item.tags.type === typeFilter
            );
        }
        
        this.totalItems = filteredData.length;
        this.calculateTotalPages();
        
        const startIndex = (this.currentPage - 1) * this.pageSize;
        const endIndex = Math.min(startIndex + this.pageSize, this.totalItems);
        const pageData = filteredData.slice(startIndex, endIndex);
        
        let html = '<table class="data-table"><thead><tr><th>时间戳</th><th>值</th><th>类型</th><th>标签</th></tr></thead><tbody>';
        
        pageData.forEach(item => {
            const tags = item.tags || {};
            html += `<tr>
                <td>${item.timestamp ? new Date(item.timestamp).toLocaleString() : '未知'}</td>
                <td>${item.value || 0}</td>
                <td>${tags.type || '未知'}</td>
                <td>${Object.entries(tags).filter(([k]) => k !== 'type').map(([k, v]) => `${k}:${v}`).join(', ') || '无'}</td>
            </tr>`;
        });
        
        html += '</tbody></table>';
        document.getElementById('data-table').innerHTML = html;
    }
    
    async loadPluginsPage() {
        const businessInfo = await this.apiCall('/business');
        const plugins = businessInfo.plugins || [];
        this.totalItems = plugins.length;
        this.calculateTotalPages();
        
        const startIndex = (this.currentPage - 1) * this.pageSize;
        const endIndex = Math.min(startIndex + this.pageSize, this.totalItems);
        const pagePlugins = plugins.slice(startIndex, endIndex);
        
        let html = '<table class="data-table"><thead><tr><th>插件名称</th><th>状态</th></tr></thead><tbody>';
        
        pagePlugins.forEach(pluginName => {
            html += `<tr>
                <td>${pluginName || '未知'}</td>
                <td><span class="status-indicator status-online"></span> 已安装</td>
            </tr>`;
        });
        
        html += '</tbody></table>';
        document.getElementById('plugins-list').innerHTML = html;
    }
    
    updateStatCard(elementId, value) {
        const element = document.getElementById(elementId);
        if (element) {
            element.textContent = value;
        }
    }
    
    showNotification(message, type = 'info') {
        // 移除现有通知
        const existing = document.querySelector('.notification');
        if (existing) {
            existing.remove();
        }
        
        const notification = document.createElement('div');
        notification.className = `notification ${type}`;
        notification.textContent = message;
        
        document.body.appendChild(notification);
        
        // 3秒后自动移除
        setTimeout(() => {
            if (notification.parentNode) {
                notification.remove();
            }
        }, 3000);
    }
}

// 全局实例
const metadataManager = new MetadataManager();

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', () => {
    console.log('Stock-TSDB 元数据管理界面已加载');
});