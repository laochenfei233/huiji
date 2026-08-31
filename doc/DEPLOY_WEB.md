# 言记 Web 版部署指南（宝塔面板）

## 构建

```bash
flutter build web --release
```

输出目录：`build/web/`

---

## 一、服务器准备

1. 宝塔面板 → **软件商店** → 安装 **Nginx**（1.24+）
2. 如需百炼 WebSocket ASR → 还需安装 **Node.js**

---

## 二、上传构建产物

将 `build/web/` 下的 **全部文件** 上传到服务器 `/www/wwwroot/yanji/`

### 方式 A：宝塔文件管理器
直接拖拽上传整个 `build/web/` 目录内容

### 方式 B：SCP 命令
```bash
scp -r build/web/* root@服务器IP:/www/wwwroot/yanji/
```

---

## 三、宝塔创建站点

1. 宝塔面板 → **网站** → **添加站点**
2. 域名：填你的域名或 IP
3. 根目录：`/www/wwwroot/yanji`
4. PHP 版本：选 **纯静态**（不需要 PHP）

---

## 四、Nginx 配置

站点设置 → 配置文件，替换为：

```nginx
server {
    listen 80;
    server_name 你的域名或IP;
    root /www/wwwroot/yanji;
    index index.html;

    # SPA 路由回退（Flutter Web 必须）
    location / {
        try_files $uri $uri/ /index.html;
    }

    # gzip 压缩
    gzip on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json
               application/javascript text/xml application/wasm;

    # 静态资源长缓存（Flutter 构建产物自带 hash）
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|wasm)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # WebSocket 代理（百炼 ASR 认证头转发）
    location /ws-proxy/ {
        proxy_pass http://127.0.0.1:8880/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
```

保存后 Nginx 自动重载。

---

## 五、WebSocket 代理（百炼 ASR 专用）

浏览器 WebSocket 无法设置 `Authorization` header，需通过代理转发。

### 5.1 上传 ws_proxy.js

将项目根目录的 `ws_proxy.js` 上传到服务器，例如 `/www/wwwroot/yanji/ws_proxy.js`

### 5.2 确认 API Key

打开 `ws_proxy.js`，确认第 13 行的 API Key 是你的百炼 Key：

```js
const API_KEY = process.env.DASHSCOPE_API_KEY || '你的API_KEY';
```

### 5.3 安装依赖 & 启动

```bash
cd /www/wwwroot/yanji
npm init -y
npm install ws
pm2 start ws_proxy.js --name yanji-ws-proxy
pm2 save
pm2 startup
```

### 5.4 Web 端 ASR 配置

在言记设置页添加 ASR 模型时：

- 类型：`websocket`
- URL：`ws://你的域名/ws-proxy/`

---

## 六、HTTPS（推荐）

宝塔面板 → 网站 → 设置 → **SSL** → **Let's Encrypt** → 免费申请 → 开启强制 HTTPS

---

## 七、防火墙

放行端口：**80**（HTTP）、**443**（HTTPS）

宝塔面板 → **安全** → **系统防火墙** → 添加规则

---

## 八、验证

浏览器访问 `http://你的域名`，应看到言记首页。

### 功能验证清单

| 功能 | 预期 |
|------|------|
| 首页/会议列表 | 正常显示 |
| 新建会议 → 录音页 | 可进入，麦克风权限弹窗 |
| 云端 ASR 识别 | 需配置 WebSocket 代理 |
| 云端 LLM 摘要 | 正常（HTTP API，无需代理） |
| 设置页 → 本地模型管理 | 显示"网页端暂不支持" |
| 导出文件 | 触发浏览器下载 |
| 导入文件 | 弹出文件选择器 |

---

## 常见问题

### 白屏 / 404
- 检查 Nginx `try_files` 配置是否正确
- 确认文件上传到了正确目录

### 录音无响应
- 浏览器需 HTTPS 才能使用麦克风（localhost 除外）
- 检查浏览器权限设置

### ASR 连接失败
- 确认 `ws_proxy.js` 正在运行：`pm2 list`
- 确认 Nginx 的 `/ws-proxy/` 路径配置正确
- 检查防火墙是否放行了 8880 端口

### 页面加载慢
- 确认 gzip 已开启
- `main.dart.js` 约 400KB，首次加载后会缓存
