# BeeCount 云端数据存储技术方案

## 1. 概述

本文档详细描述了BeeCount记账应用从离线数据存储改造为线上数据存储的完整技术方案。方案采用混合架构，既支持云端数据存储，又保持本地数据的离线可用性。

## 2. 系统架构

### 2.1 整体架构图

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Flutter App   │    │   Sync Service  │    │   Cloud DB      │
│                 │    │                 │    │   (Supabase)    │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ UI Layer    │ │◄──►│ │ Sync Layer  │ │◄──►│ │ Tables      │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ Business    │ │◄──►│ │ Repository  │ │◄──►│ │ Functions   │ │
│ │ Logic       │ │    │ │ Layer       │ │    │ └─────────────┘ │
│ └─────────────┘ │    │ └─────────────┘ │    │ ┌─────────────┐ │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ │ Realtime    │ │
│ │ Local DB    │ │◄──►│ │ Local Cache │ │◄──►│ │ Subscriptions│ │
│ │ (SQLite)    │ │    │ └─────────────┘ │    │ └─────────────┘ │
│ └─────────────┘ │    │                 │    │ ┌─────────────┐ │
│                 │    │                 │    │ │ Auth        │ │
│                 │    │                 │    │ │ (JWT)       │ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### 2.2 核心组件

- **Local DB**: 本地SQLite数据库，用于离线存储和缓存
- **Cloud DB**: Supabase PostgreSQL数据库，作为主数据源
- **Sync Service**: 同步服务，管理本地与云端的数据同步
- **Repository Layer**: 数据访问层，抽象本地和云端数据源
- **Realtime Subscriptions**: 实时数据同步

## 3. 数据库设计

### 3.1 云端数据库表结构

#### 3.1.1 用户表 (users)

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_sync_at TIMESTAMP WITH TIME ZONE,
    device_id VARCHAR(255),
    app_version VARCHAR(20)
);
```

#### 3.1.2 账本表 (ledgers)

```sql
CREATE TABLE ledgers (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    currency VARCHAR(3) DEFAULT 'CNY',
    type VARCHAR(20) DEFAULT 'personal', -- personal, shared
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    
    -- 同步字段
    server_id INTEGER,
    synced_at TIMESTAMP WITH TIME ZONE,
    is_synced BOOLEAN DEFAULT false,
    sync_error TEXT,
    
    -- 乐观锁
    version INTEGER DEFAULT 1
);
```

#### 3.1.3 账户表 (accounts)

```sql
CREATE TABLE accounts (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    ledger_id INTEGER REFERENCES ledgers(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(50) DEFAULT 'cash', -- cash, bank, credit, investment
    currency VARCHAR(3) DEFAULT 'CNY',
    initial_balance DECIMAL(15,2) DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    
    -- 同步字段
    server_id INTEGER,
    synced_at TIMESTAMP WITH TIME ZONE,
    is_synced BOOLEAN DEFAULT false,
    sync_error TEXT,
    
    -- 乐观锁
    version INTEGER DEFAULT 1
);
```

#### 3.1.4 分类表 (categories)

```sql
CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    kind VARCHAR(20) NOT NULL, -- expense, income
    icon VARCHAR(100),
    icon_type VARCHAR(20) DEFAULT 'material', -- material, custom, community
    custom_icon_path TEXT,
    community_icon_id VARCHAR(100),
    parent_id INTEGER REFERENCES categories(id),
    level INTEGER DEFAULT 1,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    
    -- 同步字段
    server_id INTEGER,
    synced_at TIMESTAMP WITH TIME ZONE,
    is_synced BOOLEAN DEFAULT false,
    sync_error TEXT,
    
    -- 乐观锁
    version INTEGER DEFAULT 1
);
```

#### 3.1.5 交易表 (transactions)

```sql
CREATE TABLE transactions (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    ledger_id INTEGER REFERENCES ledgers(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL, -- expense, income, transfer
    amount DECIMAL(15,2) NOT NULL,
    category_id INTEGER REFERENCES categories(id),
    account_id INTEGER REFERENCES accounts(id),
    to_account_id INTEGER REFERENCES accounts(id),
    happened_at TIMESTAMP WITH TIME ZONE NOT NULL,
    note TEXT,
    recurring_id INTEGER REFERENCES recurring_transactions(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    
    -- 同步字段
    server_id INTEGER,
    synced_at TIMESTAMP WITH TIME ZONE,
    is_synced BOOLEAN DEFAULT false,
    sync_error TEXT,
    
    -- 乐观锁
    version INTEGER DEFAULT 1,
    
    -- 索引
    INDEX idx_transactions_ledger_id (ledger_id),
    INDEX idx_transactions_account_id (account_id),
    INDEX idx_transactions_category_id (category_id),
    INDEX idx_transactions_happened_at (happened_at)
);
```

#### 3.1.6 标签表 (tags)

```sql
CREATE TABLE tags (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    color VARCHAR(7), -- #RRGGBB format
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    
    -- 同步字段
    server_id INTEGER,
    synced_at TIMESTAMP WITH TIME ZONE,
    is_synced BOOLEAN DEFAULT false,
    sync_error TEXT,
    
    -- 乐观锁
    version INTEGER DEFAULT 1,
    
    UNIQUE KEY uk_user_name (user_id, name)
);
```

#### 3.1.7 交易标签关联表 (transaction_tags)

```sql
CREATE TABLE transaction_tags (
    id SERIAL PRIMARY KEY,
    transaction_id INTEGER REFERENCES transactions(id) ON DELETE CASCADE,
    tag_id INTEGER REFERENCES tags(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE KEY uk_transaction_tag (transaction_id, tag_id)
);
```

#### 3.1.8 预算表 (budgets)

```sql
CREATE TABLE budgets (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    ledger_id INTEGER REFERENCES ledgers(id) ON DELETE CASCADE,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL,
    category_id INTEGER REFERENCES categories(id),
    amount DECIMAL(15,2) NOT NULL,
    prompt BOOLEAN DEFAULT false,
    prompt_day INTEGER,
    ignored BOOLEAN,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    
    -- 同步字段
    server_id INTEGER,
    synced_at TIMESTAMP WITH TIME ZONE,
    is_synced BOOLEAN DEFAULT false,
    sync_error TEXT,
    
    -- 乐观锁
    version INTEGER DEFAULT 1,
    
    UNIQUE KEY uk_budget_month_category (ledger_id, year, month, category_id)
);
```

#### 3.1.9 附件表 (attachments)

```sql
CREATE TABLE attachments (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    transaction_id INTEGER REFERENCES transactions(id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    original_name VARCHAR(255),
    file_size INTEGER,
    width INTEGER,
    height INTEGER,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    
    -- 同步字段
    server_id INTEGER,
    synced_at TIMESTAMP WITH TIME ZONE,
    is_synced BOOLEAN DEFAULT false,
    sync_error TEXT,
    
    -- 乐观锁
    version INTEGER DEFAULT 1
);
```

#### 3.1.10 重复交易表 (recurring_transactions)

```sql
CREATE TABLE recurring_transactions (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    ledger_id INTEGER REFERENCES ledgers(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL,
    amount DECIMAL(15,2) NOT NULL,
    category_id INTEGER REFERENCES categories(id),
    account_id INTEGER REFERENCES accounts(id),
    to_account_id INTEGER REFERENCES accounts(id),
    note TEXT,
    frequency VARCHAR(20) NOT NULL, -- daily, weekly, monthly, yearly
    interval INTEGER DEFAULT 1,
    day_of_month INTEGER,
    day_of_week INTEGER,
    month_of_year INTEGER,
    start_date DATE NOT NULL,
    end_date DATE,
    last_generated_date DATE,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE,
    
    -- 同步字段
    server_id INTEGER,
    synced_at TIMESTAMP WITH TIME ZONE,
    is_synced BOOLEAN DEFAULT false,
    sync_error TEXT,
    
    -- 乐观锁
    version INTEGER DEFAULT 1
);
```

#### 3.1.11 同步状态表 (sync_status)

```sql
CREATE TABLE sync_status (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    table_name VARCHAR(50) NOT NULL,
    last_sync_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_sync_count INTEGER DEFAULT 0,
    error_count INTEGER DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE KEY uk_user_table (user_id, table_name)
);
```

#### 3.1.12 设备表 (devices)

```sql
CREATE TABLE devices (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(255) NOT NULL,
    device_name VARCHAR(255),
    platform VARCHAR(50),
    app_version VARCHAR(50),
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE KEY uk_user_device (user_id, device_id)
);
```

### 3.2 数据库约束和索引

#### 3.2.1 主要约束

```sql
-- 账户余额约束
ALTER TABLE accounts ADD CONSTRAINT chk_initial_balance CHECK (initial_balance >= 0);

-- 交易金额约束
ALTER TABLE transactions ADD CONSTRAINT chk_amount_positive CHECK (amount > 0);

-- 分类层级约束
ALTER TABLE categories ADD CONSTRAINT chk_level CHECK (level >= 1 AND level <= 3);

-- 预算金额约束
ALTER TABLE budgets ADD CONSTRAINT chk_budget_amount CHECK (amount >= 0);

-- 日期范围约束
ALTER TABLE recurring_transactions ADD CONSTRAINT chk_date_range 
    CHECK (start_date <= COALESCE(end_date, start_date));
```

#### 3.2.2 性能索引

```sql
-- 交易查询索引
CREATE INDEX idx_transactions_user_ledger_date ON transactions(user_id, ledger_id, happened_at);
CREATE INDEX idx_transactions_user_account ON transactions(user_id, account_id);

-- 分类查询索引
CREATE INDEX idx_categories_user_kind ON categories(user_id, kind);
CREATE INDEX idx_categories_user_parent ON categories(user_id, parent_id);

-- 预算查询索引
CREATE INDEX idx_budgets_user_ledger_year_month ON budgets(user_id, ledger_id, year, month);

-- 同步状态索引
CREATE INDEX idx_sync_status_user_table ON sync_status(user_id, table_name);
```

## 4. API接口设计

### 4.1 认证接口

#### 4.1.1 用户注册

```http
POST /api/auth/register
Content-Type: application/json

{
    "email": "user@example.com",
    "password": "securepassword123"
}

Response:
{
    "success": true,
    "user": {
        "id": "uuid",
        "email": "user@example.com",
        "created_at": "2024-01-01T00:00:00Z"
    },
    "token": "jwt_token_here"
}
```

#### 4.1.2 用户登录

```http
POST /api/auth/login
Content-Type: application/json

{
    "email": "user@example.com",
    "password": "securepassword123"
}

Response:
{
    "success": true,
    "user": {
        "id": "uuid",
        "email": "user@example.com",
        "last_login": "2024-01-01T00:00:00Z"
    },
    "token": "jwt_token_here"
}
```

#### 4.1.3 刷新令牌

```http
POST /api/auth/refresh
Authorization: Bearer jwt_token_here

Response:
{
    "success": true,
    "token": "new_jwt_token_here",
    "expires_in": 3600
}
```

### 4.2 数据同步接口

#### 4.2.1 获取增量数据

```http
GET /api/sync/changes?since=2024-01-01T00:00:00Z&tables=transactions,categories,accounts
Authorization: Bearer jwt_token_here

Response:
{
    "success": true,
    "changes": {
        "transactions": [
            {
                "id": 1,
                "server_id": 1001,
                "user_id": "uuid",
                "ledger_id": 1,
                "type": "expense",
                "amount": 100.00,
                "category_id": 1,
                "account_id": 1,
                "happened_at": "2024-01-01T10:00:00Z",
                "note": "Lunch",
                "synced_at": "2024-01-01T10:00:00Z",
                "version": 1
            }
        ],
        "categories": [...],
        "accounts": [...]
    },
    "timestamp": "2024-01-01T10:00:00Z"
}
```

#### 4.2.2 批量上传数据

```http
POST /api/sync/upload
Authorization: Bearer jwt_token_here
Content-Type: application/json

{
    "device_id": "device_123",
    "app_version": "1.0.0",
    "changes": {
        "transactions": [
            {
                "id": null,  // null表示新记录
                "ledger_id": 1,
                "type": "income",
                "amount": 2000.00,
                "category_id": 2,
                "account_id": 1,
                "happened_at": "2024-01-02T09:00:00Z",
                "note": "Salary",
                "version": 1
            }
        ],
        "categories": [...]
    }
}

Response:
{
    "success": true,
    "results": {
        "transactions": [
            {
                "client_id": null,
                "server_id": 1002,
                "status": "created",
                "version": 1
            }
        ],
        "categories": [...]
    },
    "timestamp": "2024-01-01T10:00:00Z"
}
```

#### 4.2.3 冲突解决

```http
POST /api/sync/conflict
Authorization: Bearer jwt_token_here
Content-Type: application/json

{
    "table": "transactions",
    "record_id": 1001,
    "client_version": 2,
    "server_version": 3,
    "client_data": {
        "amount": 150.00,
        "note": "Updated lunch"
    },
    "server_data": {
        "amount": 100.00,
        "note": "Lunch"
    },
    "resolution": "client_wins"  // 或 "server_wins", "merge"
}

Response:
{
    "success": true,
    "resolved_data": {
        "id": 1001,
        "amount": 150.00,
        "note": "Updated lunch",
        "version": 4
    }
}
```

### 4.3 数据查询接口

#### 4.3.1 获取账本列表

```http
GET /api/ledgers
Authorization: Bearer jwt_token_here

Response:
{
    "success": true,
    "ledgers": [
        {
            "id": 1,
            "server_id": 1001,
            "name": "Personal",
            "currency": "CNY",
            "type": "personal",
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z",
            "synced_at": "2024-01-01T00:00:00Z",
            "version": 1
        }
    ]
}
```

#### 4.3.2 获取交易列表

```http
GET /api/transactions?ledger_id=1&start_date=2024-01-01&end_date=2024-01-31&page=1&limit=20
Authorization: Bearer jwt_token_here

Response:
{
    "success": true,
    "transactions": [
        {
            "id": 1,
            "server_id": 1001,
            "ledger_id": 1,
            "type": "expense",
            "amount": 100.00,
            "category_id": 1,
            "account_id": 1,
            "happened_at": "2024-01-01T10:00:00Z",
            "note": "Lunch",
            "created_at": "2024-01-01T10:00:00Z",
            "updated_at": "2024-01-01T10:00:00Z",
            "synced_at": "2024-01-01T10:00:00Z",
            "version": 1,
            "category": {
                "id": 1,
                "name": "Food",
                "icon": "restaurant"
            },
            "account": {
                "id": 1,
                "name": "Cash",
                "type": "cash"
            }
        }
    ],
    "pagination": {
        "page": 1,
        "limit": 20,
        "total": 150,
        "pages": 8
    }
}
```

#### 4.3.3 统计数据接口

```http
GET /api/statistics/summary?ledger_id=1&start_date=2024-01-01&end_date=2024-01-31
Authorization: Bearer jwt_token_here

Response:
{
    "success": true,
    "summary": {
        "income": 5000.00,
        "expense": 3000.00,
        "balance": 2000.00,
        "categories": [
            {
                "id": 1,
                "name": "Food",
                "icon": "restaurant",
                "total": 500.00,
                "percentage": 16.67
            }
        ],
        "accounts": [
            {
                "id": 1,
                "name": "Cash",
                "balance": 1500.00,
                "type": "cash"
            }
        ]
    }
}
```

### 4.4 实时订阅

#### 4.4.1 订阅数据变更

```javascript
// 使用 Supabase Realtime
const channel = supabase
    .channel('public:transactions')
    .on(
        'postgres_changes',
        {
            event: '*',
            schema: 'public',
            table: 'transactions',
            filter: `user_id=eq.${userId}`
        },
        (payload) => {
            console.log('Transaction changed:', payload);
            // 处理实时数据变更
        }
    )
    .subscribe();
```

## 5. 同步策略

### 5.1 同步模式

#### 5.1.1 实时同步
- **触发条件**: 用户操作（增删改）
- **实现方式**: 立即调用云端API
- **优点**: 数据实时性高
- **缺点**: 网络消耗大

#### 5.1.2 定时同步
- **触发条件**: 定时器（如每5分钟）
- **实现方式**: 批量同步未同步的数据
- **优点**: 减少网络请求
- **缺点**: 数据有一定延迟

#### 5.1.3 手动同步
- **触发条件**: 用户手动触发
- **实现方式**: 全量或增量同步
- **优点**: 用户可控
- **缺点**: 依赖用户操作

### 5.2 冲突解决策略

#### 5.2.1 时间戳优先
```dart
enum ConflictResolution {
    CLIENT_WINS,    // 客户端版本优先
    SERVER_WINS,    // 服务端版本优先
    MERGE,          // 合并策略
    MANUAL          // 手动解决
}

// 冲突检测逻辑
bool hasConflict(LocalRecord local, ServerRecord server) {
    return local.version != server.version;
}

// 解决策略
ServerRecord resolveConflict(LocalRecord local, ServerRecord server, ConflictResolution strategy) {
    switch (strategy) {
        case ConflictResolution.CLIENT_WINS:
            return ServerRecord.fromLocal(local);
        case ConflictResolution.SERVER_WINS:
            return server;
        case ConflictResolution.MERGE:
            return mergeRecords(local, server);
        default:
            throw ConflictException('Manual resolution required');
    }
}
```

#### 5.2.2 字段级合并
```dart
ServerRecord mergeRecords(LocalRecord local, ServerRecord server) {
    return ServerRecord(
        id: server.id,
        amount: local.amount,  // 金额以客户端为准
        note: server.note,     // 备注以服务端为准
        category_id: local.category_id,  // 分类以客户端为准
        // ... 其他字段
    );
}
```

### 5.3 离线策略

#### 5.3.1 本地优先
```dart
class OfflineFirstRepository implements TransactionRepository {
    @override
    Future<int> addTransaction({...}) async {
        // 1. 先保存到本地
        final localId = await _localRepo.addTransaction(...);
        
        // 2. 尝试同步到云端
        try {
            await _syncService.syncTransaction(localId);
        } catch (e) {
            // 3. 同步失败，标记为待同步
            await _localRepo.markAsPendingSync(localId);
        }
        
        return localId;
    }
}
```

#### 5.3.2 待同步队列
```dart
class PendingSyncQueue {
    Future<void> addToQueue(SyncOperation operation) async {
        await _db.insert('pending_sync', {
            'operation_type': operation.type,
            'data': jsonEncode(operation.data),
            'created_at': DateTime.now(),
            'retry_count': 0
        });
    }
    
    Future<void> processQueue() async {
        final operations = await _db.query('pending_sync', limit: 100);
        
        for (final op in operations) {
            try {
                await _syncService.execute(op);
                await _db.delete('pending_sync', where: 'id = ?', whereArgs: [op['id']]);
            } catch (e) {
                await _db.update('pending_sync', {
                    'retry_count': op['retry_count'] + 1,
                    'last_error': e.toString()
                }, where: 'id = ?', whereArgs: [op['id']]);
            }
        }
    }
}
```

## 6. 安全设计

### 6.1 数据加密

#### 6.1.1 传输加密
- 使用 HTTPS/TLS 1.3
- 实施证书固定（Certificate Pinning）
- 启用 HSTS

#### 6.1.2 存储加密
```dart
class EncryptedStorage {
    final FlutterSecureStorage _storage = FlutterSecureStorage();
    final AesCrypt _aesCrypt = AesCrypt();
    
    Future<void> saveEncrypted(String key, String data) async {
        final encrypted = _aesCrypt.encrypt(data, _getEncryptionKey());
        await _storage.write(key: key, value: encrypted);
    }
    
    Future<String?> readEncrypted(String key) async {
        final encrypted = await _storage.read(key: key);
        if (encrypted == null) return null;
        return _aesCrypt.decrypt(encrypted, _getEncryptionKey());
    }
    
    String _getEncryptionKey() {
        // 从系统密钥链获取或生成
        return _storage.read(key: 'encryption_key') ?? _generateKey();
    }
}
```

### 6.2 权限控制

#### 6.2.1 基于角色的访问控制（RBAC）
```sql
-- 用户角色表
CREATE TABLE user_roles (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    role VARCHAR(50) NOT NULL, -- owner, viewer, editor
    resource_type VARCHAR(50), -- ledger, account, transaction
    resource_id INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 权限检查函数
CREATE OR REPLACE FUNCTION check_permission(
    p_user_id UUID,
    p_role VARCHAR,
    p_resource_type VARCHAR,
    p_resource_id INTEGER
) RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM user_roles 
        WHERE user_id = p_user_id 
        AND role = p_role
        AND (resource_type IS NULL OR resource_type = p_resource_type)
        AND (resource_id IS NULL OR resource_id = p_resource_id)
    );
END;
$$ LANGUAGE plpgsql;
```

#### 6.2.2 行级安全策略（RLS）
```sql
-- 启用 RLS
ALTER TABLE ledgers ENABLE ROW LEVEL SECURITY;

-- 创建策略
CREATE POLICY ledgers_user_policy ON ledgers
    FOR ALL
    USING (user_id = current_setting('app.current_user_id')::UUID);

-- 应用策略
ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY accounts_user_policy ON accounts
    FOR ALL
    USING (user_id = current_setting('app.current_user_id')::UUID);
```

### 6.3 审计日志

```sql
-- 审计日志表
CREATE TABLE audit_logs (
    id SERIAL PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    action VARCHAR(50) NOT NULL, -- create, update, delete, sync
    resource_type VARCHAR(50),
    resource_id INTEGER,
    old_data JSONB,
    new_data JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 触发器函数
CREATE OR REPLACE FUNCTION log_audit() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_logs (
        user_id, action, resource_type, resource_id, old_data, new_data
    ) VALUES (
        current_setting('app.current_user_id')::UUID,
        TG_OP,
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        CASE WHEN TG_OP = 'DELETE' THEN row_to_json(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) ELSE NULL END
    );
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- 创建触发器
CREATE TRIGGER audit_ledgers AFTER INSERT OR UPDATE OR DELETE ON ledgers
    FOR EACH ROW EXECUTE FUNCTION log_audit();
```

## 7. 性能优化

### 7.1 数据库优化

#### 7.1.1 查询优化
```sql
-- 分页查询优化
CREATE INDEX idx_transactions_pagination ON transactions(user_id, ledger_id, happened_at DESC, id);

-- 统计查询优化
CREATE INDEX idx_transactions_stats ON transactions(user_id, ledger_id, type, happened_at);

-- 分类统计优化
CREATE INDEX idx_categories_stats ON categories(user_id, kind, parent_id);
```

#### 7.1.2 缓存策略
```dart
class CacheService {
    final Map<String, CacheEntry> _cache = {};
    final Duration _defaultTTL = Duration(minutes: 5);
    
    Future<T?> get<T>(String key) async {
        final entry = _cache[key];
        if (entry == null || entry.isExpired()) {
            _cache.remove(key);
            return null;
        }
        return entry.data as T;
    }
    
    Future<void> set<T>(String key, T data, {Duration? ttl}) async {
        _cache[key] = CacheEntry(
            data: data,
            expiry: DateTime.now().add(ttl ?? _defaultTTL)
        );
    }
    
    Future<void> invalidate(String pattern) async {
        _cache.removeWhere((key, _) => key.contains(pattern));
    }
}

class CacheEntry<T> {
    final T data;
    final DateTime expiry;
    
    CacheEntry({required this.data, required this.expiry});
    
    bool isExpired() => DateTime.now().isAfter(expiry);
}
```

### 7.2 网络优化

#### 7.2.1 数据压缩
```dart
class CompressionService {
    Future<String> compress(String data) async {
        final bytes = utf8.encode(data);
        final compressed = gzip.encode(bytes);
        return base64Encode(compressed);
    }
    
    Future<String> decompress(String compressedData) async {
        final bytes = base64Decode(compressedData);
        final decompressed = gzip.decode(bytes);
        return utf8.decode(decompressed);
    }
}
```

#### 7.2.2 批量请求
```dart
class BatchRequestService {
    final List<Request> _queue = [];
    final Duration _batchWindow = Duration(seconds: 2);
    
    Future<void> queueRequest(Request request) async {
        _queue.add(request);
        
        if (_queue.length >= 10) {
            await _flushBatch();
        } else {
            // 延迟flush，等待更多请求
            Future.delayed(_batchWindow, () {
                if (_queue.isNotEmpty) {
                    _flushBatch();
                }
            });
        }
    }
    
    Future<void> _flushBatch() async {
        if (_queue.isEmpty) return;
        
        final batch = _queue.take(10).toList();
        _queue.removeRange(0, batch.length);
        
        await _sendBatchRequest(batch);
    }
}
```

## 8. 错误处理

### 8.1 错误分类

```dart
enum SyncErrorType {
    NETWORK_ERROR,      // 网络连接问题
    AUTH_ERROR,         // 认证失败
    CONFLICT_ERROR,     // 数据冲突
    VALIDATION_ERROR,   // 数据验证失败
    SERVER_ERROR,       // 服务器错误
    TIMEOUT_ERROR       // 请求超时
}

class SyncError extends Error {
    final SyncErrorType type;
    final String message;
    final dynamic details;
    
    SyncError(this.type, this.message, {this.details});
}
```

### 8.2 重试机制

```dart
class RetryService {
    static const List<Duration> _retryDelays = [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 16)
    ];
    
    Future<T> withRetry<T>(
        Future<T> Function() operation,
        {int maxRetries = 5}
    ) async {
        for (var i = 0; i < maxRetries; i++) {
            try {
                return await operation();
            } catch (e) {
                if (i == maxRetries - 1) rethrow;
                
                final delay = _retryDelays[i];
                await Future.delayed(delay);
            }
        }
        throw Exception('Max retries exceeded');
    }
}
```

## 9. 监控和日志

### 9.1 性能监控

```dart
class PerformanceMonitor {
    final Map<String, List<Duration>> _metrics = {};
    
    Future<T> measure<T>(String operation, Future<T> Function() fn) async {
        final start = DateTime.now();
        
        try {
            final result = await fn();
            final duration = DateTime.now().difference(start);
            
            _recordMetric(operation, duration);
            return result;
        } catch (e) {
            final duration = DateTime.now().difference(start);
            _recordMetric('${operation}_error', duration);
            rethrow;
        }
    }
    
    void _recordMetric(String operation, Duration duration) {
        _metrics.putIfAbsent(operation, () => []);
        _metrics[operation]!.add(duration);
        
        // 保持最近100条记录
        if (_metrics[operation]!.length > 100) {
            _metrics[operation]!.removeRange(0, 50);
        }
    }
    
    Map<String, Duration> getStats() {
        return _metrics.map((key, value) {
            final avg = Duration(
                microseconds: value.map((d) => d.inMicroseconds).reduce((a, b) => a + b) ~/ value.length
            );
            final max = value.reduce((a, b) => a.inMicroseconds > b.inMicroseconds ? a : b);
            return MapEntry(key, avg);
        });
    }
}
```

### 9.2 日志系统

```dart
class LoggerService {
    static final LoggerService _instance = LoggerService._internal();
    
    factory LoggerService() => _instance;
    
    LoggerService._internal();
    
    void info(String tag, String message, [Object? data]) {
        _log(Level.INFO, tag, message, data);
    }
    
    void warning(String tag, String message, [Object? data]) {
        _log(Level.WARNING, tag, message, data);
    }
    
    void error(String tag, String message, [Object? error, StackTrace? stackTrace]) {
        _log(Level.ERROR, tag, message, error, stackTrace);
    }
    
    void _log(Level level, String tag, String message, [Object? data, StackTrace? stackTrace]) {
        final logEntry = LogEntry(
            level: level,
            tag: tag,
            message: message,
            data: data,
            timestamp: DateTime.now(),
            stackTrace: stackTrace
        );
        
        // 控制台输出
        print(logEntry.toString());
        
        // 文件记录
        _writeToFile(logEntry);
        
        // 远程日志（可选）
        if (level == Level.ERROR) {
            _sendToRemoteLogger(logEntry);
        }
    }
}
```

## 10. 部署和运维

### 10.1 环境配置

#### 10.1.1 开发环境
```yaml
# docker-compose.yml
version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: beecount_dev
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: dev_password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  supabase:
    image: supabase/postgres:15
    environment:
      POSTGRES_DB: beecount_dev
      POSTGRES_USER: supabase_user
      POSTGRES_PASSWORD: supabase_password
    ports:
      - "5432:5432"
```

#### 10.1.2 生产环境
```yaml
# kubernetes/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: beecount-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: beecount-api
  template:
    metadata:
      labels:
        app: beecount-api
    spec:
      containers:
      - name: api
        image: beecount/api:latest
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: database-url
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: jwt-secret
              key: secret
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

### 10.2 数据备份

```bash
#!/bin/bash
# backup.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/$DATE"
mkdir -p $BACKUP_DIR

# 数据库备份
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME | gzip > $BACKUP_DIR/database_$DATE.sql.gz

# 附件备份
tar -czf $BACKUP_DIR/attachments_$DATE.tar.gz /app/uploads

# 上传到云存储
aws s3 cp $BACKUP_DIR s3://beecount-backups/$DATE/ --recursive

# 清理旧备份（保留30天）
find /backups -type d -mtime +30 -exec rm -rf {} \;
```

### 10.3 监控告警

```yaml
# prometheus.yml
global:
  scrape_interval: 15s

rule_files:
  - "alert_rules.yml"

scrape_configs:
  - job_name: 'beecount-api'
    static_configs:
      - targets: ['api:3000']
    metrics_path: '/metrics'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']
```

```yaml
# alert_rules.yml
groups:
- name: beecount-alerts
  rules:
  - alert: HighErrorRate
    expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "High error rate detected"
      
  - alert: DatabaseDown
    expr: up{job="beecount-api"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Database is down"
```

## 11. 测试策略

### 11.1 单元测试

```dart
@GenerateMocks([TransactionRepository, SyncService])
void main() {
    late TransactionRepository mockRepo;
    late SyncService mockSyncService;
    late TransactionService service;

    setUp(() {
        mockRepo = MockTransactionRepository();
        mockSyncService = MockSyncService();
        service = TransactionService(mockRepo, mockSyncService);
    });

    group('addTransaction', () {
        test('should save locally and sync to cloud', () async {
            // Arrange
            when(mockRepo.addTransaction(any)).thenAnswer((_) async => 1);
            when(mockSyncService.syncTransaction(any)).thenAnswer((_) async => null);

            // Act
            final result = await service.addTransaction(
                ledgerId: 1,
                type: 'expense',
                amount: 100.0,
                categoryId: 1,
                accountId: 1,
                happenedAt: DateTime.now()
            );

            // Assert
            expect(result, equals(1));
            verify(mockRepo.addTransaction(any)).called(1);
            verify(mockSyncService.syncTransaction(1)).called(1);
        });

        test('should handle sync failure gracefully', () async {
            // Arrange
            when(mockRepo.addTransaction(any)).thenAnswer((_) async => 1);
            when(mockSyncService.syncTransaction(any)).thenThrow(Exception('Sync failed'));

            // Act & Assert
            expect(() => service.addTransaction(
                ledgerId: 1,
                type: 'expense',
                amount: 100.0,
                categoryId: 1,
                accountId: 1,
                happenedAt: DateTime.now()
            ), returnsNormally);
        });
    });
}
```

### 11.2 集成测试

```dart
void main() {
    late TestDatabase testDb;
    late TransactionRepository repository;

    setUp(() async {
        testDb = await TestDatabase.create();
        repository = LocalTransactionRepository(testDb.database);
    });

    tearDown(() async {
        await testDb.close();
    });

    test('transaction CRUD operations', () async {
        // Create
        final id = await repository.addTransaction(
            ledgerId: 1,
            type: 'expense',
            amount: 100.0,
            categoryId: 1,
            accountId: 1,
            happenedAt: DateTime.now()
        );
        expect(id, isPositive);

        // Read
        final transaction = await repository.getTransactionById(id);
        expect(transaction, isNotNull);
        expect(transaction!.amount, equals(100.0));

        // Update
        await repository.updateTransaction(
            id: id,
            type: 'expense',
            amount: 150.0,
            categoryId: 1
        );

        final updated = await repository.getTransactionById(id);
        expect(updated!.amount, equals(150.0));

        // Delete
        await repository.deleteTransaction(id);
        final deleted = await repository.getTransactionById(id);
        expect(deleted, isNull);
    });
}
```

### 11.3 端到端测试

```dart
void main() {
    testWidgets('full transaction flow', (WidgetTester tester) async {
        // Setup app
        await tester.pumpWidget(BeecountApp());

        // Navigate to add transaction
        await tester.tap(find.byKey(const Key('add_transaction_button')));
        await tester.pumpAndSettle();

        // Fill form
        await tester.enterText(find.byKey(const Key('amount_field')), '100.00');
        await tester.tap(find.byKey(const Key('category_dropdown')));
        await tester.tap(find.text('Food'));
        await tester.tap(find.byKey(const Key('account_dropdown')));
        await tester.tap(find.text('Cash'));

        // Save
        await tester.tap(find.byKey(const Key('save_button')));
        await tester.pumpAndSettle();

        // Verify
        expect(find.text('100.00'), findsOneWidget);
        expect(find.text('Food'), findsOneWidget);
        expect(find.text('Cash'), findsOneWidget);
    });
}
```

## 12. 迁移计划

### 12.1 阶段一：基础设施准备（1-2周）

1. **数据库迁移**
   - 创建云端数据库结构
   - 实施数据迁移脚本
   - 验证数据完整性

2. **API开发**
   - 实现基础CRUD接口
   - 实现认证和授权
   - 实现数据同步接口

3. **测试环境**
   - 搭建开发和测试环境
   - 配置CI/CD流水线
   - 编写基础测试用例

### 12.2 阶段二：核心功能迁移（2-3周）

1. **数据模型改造**
   - 扩展现有数据模型
   - 添加同步字段
   - 实现乐观锁机制

2. **Repository层改造**
   - 增强LocalRepository
   - 完善CloudRepository
   - 实现SyncRepository

3. **业务逻辑适配**
   - 更新Service层
   - 修改Provider逻辑
   - 适配UI层调用

### 12.3 阶段三：同步功能实现（2-3周）

1. **同步服务开发**
   - 实现SyncService
   - 添加冲突解决逻辑
   - 实现离线队列

2. **实时同步**
   - 集成Supabase Realtime
   - 实现数据变更监听
   - 添加状态指示器

3. **用户体验优化**
   - 添加加载状态
   - 实现错误处理
   - 优化网络请求

### 12.4 阶段四：测试和发布（1-2周）

1. **全面测试**
   - 单元测试覆盖
   - 集成测试验证
   - 端到端测试

2. **性能优化**
   - 数据库查询优化
   - 网络请求优化
   - 内存使用优化

3. **发布准备**
   - 文档更新
   - 用户培训材料
   - 发布计划制定

## 13. 风险评估

### 13.1 技术风险

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| 数据迁移失败 | 中 | 高 | 制定详细迁移计划，实施前备份，分阶段迁移 |
| 网络不稳定 | 高 | 中 | 实现离线优先，优化重试机制，添加网络状态监听 |
| 性能问题 | 中 | 中 | 实施性能监控，优化查询，使用缓存策略 |
| 安全漏洞 | 低 | 高 | 实施安全审计，使用加密传输，定期安全测试 |

### 13.2 业务风险

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| 用户数据丢失 | 低 | 极高 | 实施多重备份，数据校验，回滚机制 |
| 功能不兼容 | 中 | 中 | 保持向后兼容，渐进式迁移，充分测试 |
| 用户体验下降 | 中 | 中 | 用户调研，A/B测试，快速迭代优化 |

## 14. 总结

本技术方案提供了完整的云端数据存储改造方案，包括：

1. **数据库设计**：详细的表结构设计和约束
2. **API接口**：完整的RESTful API设计
3. **同步策略**：实时同步、定时同步、冲突解决
4. **安全设计**：数据加密、权限控制、审计日志
5. **性能优化**：查询优化、缓存策略、网络优化
6. **监控运维**：性能监控、日志系统、部署配置
7. **测试策略**：单元测试、集成测试、端到端测试
8. **迁移计划**：分阶段实施计划
9. **风险评估**：技术风险和业务风险分析

通过实施本方案，BeeCount应用将实现：

- **数据安全**：端到端加密，多重备份
- **高可用性**：离线优先，实时同步
- **良好性能**：优化查询，智能缓存
- **用户体验**：无缝切换，状态可见
- **可维护性**：清晰架构，完善监控

方案采用渐进式迁移策略，确保现有功能不受影响，同时为未来的扩展和优化奠定基础。