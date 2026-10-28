# 本地部署大模型 + 接入 DeepSeek Harness 完整指南

在 Windows 电脑上部署 Ollama 本地大模型（NVIDIA RTX 5070 Laptop / 8GB 显存），并通过 OpenAI 兼容接口接入 DeepSeek Harness（DSH），也可经 OpenVPN 供局域网/公网其他电脑调用。

> 本文所有命令、踩坑与性能数据均来自实机验证（i9-14900HX + 32GB RAM + RTX 5070 Laptop 8GB，Windows 11 26200）。

> 💻 **远程使用者（电脑B）请看**：[电脑B 使用说明](docs/电脑B使用说明.md) —— 无需安装模型，连上 VPN 即可调用。

---

## 目录

- [一、硬件评估：8GB 显存能跑多大](#一硬件评估8gb-显存能跑多大)
- [二、安装 Ollama](#二安装-ollama)
- [三、下载模型（国内网络方案）](#三下载模型国内网络方案)
- [四、导入模型到 Ollama](#四导入模型到-ollama)
- [五、配置 Ollama（监听 + 调优）](#五配置-ollama监听--调优)
- [六、验证推理与 GPU 加速](#六验证推理与-gpu-加速)
- [七、接入 DeepSeek Harness（DSH）](#七接入-deepseek-harnessdsh)
- [八、远程访问（OpenVPN / 局域网）](#八远程访问openvpn--局域网)
- [九、踩坑记录（必读）](#九踩坑记录必读)
- [十、脚本文件](#十脚本文件)

---

## 一、硬件评估：8GB 显存能跑多大

8GB 显存是唯一硬天花板（笔记本显卡焊死不可升级）。实测各量级模型：

| 模型 | 量化 | 体积 | 上下文 | 实测速度 | 结论 |
|---|---|---|---|---|---|
| Qwen3-8B | Q4_K_M | 4.7 GB | 16K | **60–62 tok/s** | ✅ 100% GPU，日常主力 |
| Qwen3-8B | Q4_K_M | 4.7 GB | 32K | 27–32 tok/s | ✅ 76% GPU，长文本 |
| **Qwen3-30B-A3B**（MoE） | IQ4_XS | 15.6 GB | 16K | **37.5 tok/s** | ✅ 质量最高，Agent 首选 |
| Qwen3-14B | Q4 | ~9 GB | 16K | ~12–18 tok/s | ✅ 可用 |
| Qwen3-32B 稠密 | Q4 | ~19 GB | — | <7 tok/s | ❌ 太慢 |
| 70B+ | — | 40 GB+ | — | — | ❌ 内存都不够 |

**关键结论**：

- **8B 全速、30B-A3B MoE 是甜点**（30B 质量、每 token 只激活 3B 参数，速度只比 8B 慢 40%）。
- **上下文长度决定速度**：同一 8B 模型，16K 上下文 100% GPU = 60 tok/s；32K 上下文 24% 溢出到 CPU 就掉到 27–30 tok/s。下表：

| 上下文 | 速度 | 显存 | GPU 占比 |
|---|---|---|---|
| 16384 | 60.0 tok/s | 6.1 GB | 100% |
| 20480 | 46.9 tok/s | 6.9 GB | 89% |
| 24576 | 38.2 tok/s | 7.2 GB | 85% |
| 32768 | 27–30 tok/s | 8.0 GB | 76% |

- RTX 5070 Laptop 是 Blackwell 架构（计算能力 sm_120），**需要 CUDA 12.8+**，Ollama 需较新版本（≥0.9），老版本会静默回退 CPU、速度掉 10 倍。

---

## 二、安装 Ollama

### 2.1 下载安装包

Windows 安装包约 1.5 GB。国内直连 GitHub 极慢（实测 30 KB/s），**务必用镜像**：

```powershell
# cors.isteed.cc 实测可达 8.7 MB/s
curl.exe -L --ssl-no-revoke -C - -o "$env:TEMP\OllamaSetup.exe" `
  "https://cors.isteed.cc/https://github.com/ollama/ollama/releases/latest/download/OllamaSetup.exe"
```

> 下载过程中若中断，重复上面命令即可断点续传（`-C -`）。完整脚本见 `scripts/download-ollama.ps1`。

### 2.2 静默安装（用户级，无需管理员）

```powershell
Start-Process "$env:TEMP\OllamaSetup.exe" -ArgumentList '/VERYSILENT','/NORESTART','/SUPPRESSMSGBOXES' -Wait
```

安装到 `%LOCALAPPDATA%\Programs\Ollama`，会自动加开机自启（启动文件夹 `Ollama.lnk`）。

### 2.3 验证

```powershell
& "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe" --version
```

---

## 三、下载模型（国内网络方案）

### 3.1 为什么不用 `ollama pull`

`ollama pull` 从 `registry.ollama.ai`（Cloudflare R2，国际链路）下载，实测仅 **85–543 KB/s**，一个 5GB 模型要 1.5–10 小时；且**下载中断会导致 blob 静默损坏**（大小完全一致但内容错位，见[踩坑 §9.5](#95-ollama-下载中断导致-blob-静默损坏)）。

### 3.2 推荐：ModelScope 下载 GGUF（支持断点续传）

ModelScope（魔搭）国内可达 1 MB/s，支持 `-C -` 断点续传：

```powershell
# Qwen3-8B Q4_K_M（4.7 GB）
curl.exe -L --ssl-no-revoke -C - -o "D:\ollama-models\Qwen3-8B-Q4_K_M.gguf" `
  "https://www.modelscope.cn/models/Qwen/Qwen3-8B-GGUF/resolve/master/Qwen3-8B-Q4_K_M.gguf"

# Qwen3-30B-A3B-Instruct-2507 IQ4_XS（15.6 GB，高质量 Agent 首选）
curl.exe -L --ssl-no-revoke -C - -o "D:\ollama-models\Qwen3-30B-A3B-Instruct-2507-IQ4_XS.gguf" `
  "https://www.modelscope.cn/models/unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF/resolve/master/Qwen3-30B-A3B-Instruct-2507-IQ4_XS.gguf"
```

### 3.3 各下载源实测速度

| 源 | 速度 | 备注 |
|---|---|---|
| `cors.isteed.cc` 代理 GitHub Releases | **8.7 MB/s** | 装包首选 |
| `www.modelscope.cn` | 1.05 MB/s | GGUF 首选，支持续传 |
| `registry.ollama.ai`（ollama pull） | 85–543 KB/s | 慢且易损坏 |
| HuggingFace 直连 / hf-mirror | 30 / 36 KB/s | 不可用 |

---

## 四、导入模型到 Ollama

Ollama 支持从 GGUF 文件直接创建模型（会自动计算 blob digest，完全避开 pull 的损坏问题）。

### 4.1 写 Modelfile

```dockerfile
FROM ./Qwen3-8B-Q4_K_M.gguf

PARAMETER temperature 0.6
PARAMETER top_p 0.95
PARAMETER top_k 20
PARAMETER repeat_penalty 1.05
# 16384 是 8GB 显存的甜点：100% GPU，实测 60 tok/s
PARAMETER num_ctx 16384
```

### 4.2 创建模型

```powershell
cd D:\ollama-models
& "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe" create qwen3-8b -f Modelfile.qwen3-8b
& "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe" create qwen3-30b-a3b -f Modelfile.qwen3-30b-a3b
```

> 建议给同一个 GGUF 建两个上下文变体（如 `qwen3-8b` 16K 快 + `qwen3-8b-long` 32K 长文本），它们共用同一份权重，不额外占磁盘。

---

## 五、配置 Ollama（监听 + 调优）

### 5.1 环境变量（用户级）

```powershell
[Environment]::SetEnvironmentVariable('OLLAMA_HOST','0.0.0.0:11434','User')   # 同时服务本机与远程
[Environment]::SetEnvironmentVariable('OLLAMA_FLASH_ATTENTION','1','User')     # Blackwell 闪光注意力
[Environment]::SetEnvironmentVariable('OLLAMA_KV_CACHE_TYPE','q8_0','User')    # KV 量化，省一半显存
[Environment]::SetEnvironmentVariable('OLLAMA_NUM_PARALLEL','1','User')        # 单并发不浪费显存
[Environment]::SetEnvironmentVariable('OLLAMA_MAX_LOADED_MODELS','1','User')   # 32G 内存只驻留一个
[Environment]::SetEnvironmentVariable('OLLAMA_KEEP_ALIVE','30m','User')        # 空闲 30 分钟才卸载
```

> 设置后需重启 Ollama 进程（`ollama app` 会读这些变量）。`OLLAMA_HOST` **不支持逗号分隔多地址**（写了服务会起不来）。

### 5.2 24 小时常开（笔记本）

```powershell
# 禁用睡眠与休眠
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
# 合盖不动作
powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0
powercfg /setactive SCHEME_CURRENT
```

---

## 六、验证推理与 GPU 加速

```powershell
# 本机 OpenAI 兼容接口测试
curl.exe -sS "http://127.0.0.1:11434/v1/chat/completions" `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer ollama" `
  -d '{\"model\":\"qwen3-30b-a3b\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}'
```

看 GPU 占用（确认没回退 CPU）：

```powershell
& "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe" ps
# 应显示 100% GPU（8B/16K）或 65% CPU/35% GPU（30B MoE）
```

---

## 七、接入 DeepSeek Harness（DSH）

DSH 的模型由「**provider（路由）+ model（id）**」定位，OpenAI 兼容端点统一走 `@deepseek-ai/dsh-llm-pi-ai` 这个 provider 管理器。

### 7.1 编辑 profile 配置

文件：`%USERPROFILE%\.dsh\profiles\desktop\cordis.patch.yml`

在末尾追加（或替换已有的 `llm-pi-ai` 段）：

```yaml
- id: llm-pi-ai
  name: "@deepseek-ai/dsh-llm-pi-ai"
  config:
    providers:
      ollama-local:
        displayName: 本地 Ollama
        api: openai-completions
        baseURL: http://127.0.0.1:11434/v1
        headers:
          Authorization: "Bearer ollama"   # Ollama 无密钥，占位 token 绕过 pi-ai 强制鉴权
        models:
          - id: qwen3-30b-a3b
            name: Qwen3-30B-A3B（高质量 Agent）
            contextWindow: 16384
            maxTokens: 8192
            reasoningEfforts: false
          - id: qwen3-8b
            name: Qwen3-8B（快速）
            contextWindow: 16384
            maxTokens: 8192
          - id: qwen3-8b-long
            name: Qwen3-8B（32K 长文本）
            contextWindow: 32768
            maxTokens: 8192
```

### 7.2 字段说明（从 DSH 源码 zod schema 确认）

| 字段 | 必填 | 含义 |
|---|---|---|
| `api` | ✅ | 协议，OpenAI 兼容填 `openai-completions` |
| `baseURL` | ✅ | **必须带 `/v1`**，否则请求会打到 `/chat/completions` 而非 `/v1/chat/completions` |
| `models` | ✅ | 非空列表；每项含 `id`（必填）、`name`、`contextWindow`、`maxTokens`、`reasoningEfforts` |
| `headers` | Ollama 需 | pi-ai 的 OpenAI 实现强制要 Authorization 头，本地无密钥用占位 token |
| `displayName` | — | 选择器显示名 |
| `reasoningEfforts: false` | — | 声明非思考模型（30B-A3B 用）；思考模型省略或配 `{ off: , high: high }` |

### 7.3 生效与使用

1. **重启 DSH**（配置在 profile 里，下次启动读取）。
2. 在模型选择器里选「本地 Ollama」→ 对应模型（临时生效）。
3. 若想**默认用本地模型**，把 `cordis.patch.yml` 顶部的 `agent-default-model` 改为：

```yaml
- id: agent-default-model
  name: "@deepseek-ai/dsh-agent-default-model"
  config:
    provider: ollama-local
    model: qwen3-30b-a3b
```

### 7.4 思考模型注意

Qwen3-8B 是思考模型，默认会「先思考再答」。若 DSH 未显式传 `think` 开关，可能把 token 预算耗在思考上。**Agent 场景首选非思考的 `qwen3-30b-a3b`**，无此歧义。

---

## 八、远程访问（OpenVPN / 局域网）

Ollama 绑 `0.0.0.0:11434` 后，本机用 `127.0.0.1`、远程用其 IP 均可。

### 8.1 OpenVPN 星型拓扑

```
电脑B ──OpenVPN──> 腾讯云 VPS ──> 电脑A(10.8.0.3:11434)
```

- 远程客户端填 `http://10.8.0.3:11434/v1`（任意客户端：Cherry Studio / Chatbox / Cline）。
- **网络不是瓶颈**：20 tok/s 文本流约 0.5 Mbps，70ms 延迟只让首字慢 0.1 秒。

### 8.2 验证脚本

远程电脑上运行 `scripts/b-client-test.ps1`（测 ping、API、chat、速度）。

### 8.3 安全

- 本机防火墙默认关闭时，`0.0.0.0` 会暴露到局域网；若需限制，建议加 Caddy 反代 + API Key，或只绑 VPN 地址 `10.8.0.3:11434`（代价是本机 `127.0.0.1` 不可用）。
- 实测「只绑 VPN 地址」与「本机使用」不可兼得（`OLLAMA_HOST` 不支持多地址）。

---

## 九、踩坑记录（必读）

### 9.1 带宽误判
用清华/阿里云镜像测出「6 并发 598 KB/s」，会误判为线路只有 4.7 Mbps。**真相是源站限速**——换 `cors.isteed.cc` 达 8.7 MB/s。测带宽必须用不限速 CDN。

### 9.2 `curl` 必须加 `--ssl-no-revoke`
本机 `CRYPT_E_REVOCATION_OFFLINE`（证书吊销列表查不到），不加则所有 HTTPS 下载失败。

### 9.3 PowerShell 5.1 不认无 BOM 的 UTF-8 中文脚本
没有 `pwsh`（PowerShell 7）时，只有 5.1；中文注释会被按 GBK 解析，报 `Missing closing '}'`。**脚本必须纯 ASCII 或带 UTF-8 BOM**。

### 9.4 中文经 PowerShell 传参会变 `???`
`Invoke-RestMethod -Body $json` 默认非 UTF-8，必须：

```powershell
$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
Invoke-RestMethod ... -Body $bytes -ContentType 'application/json; charset=utf-8'
```

### 9.5 Ollama 下载中断导致 blob 静默损坏
`ollama pull` 被中断后，partial 文件**大小与目标完全一致但内容错位**；手动改名入库后 `ollama pull` 仍报 `verifying sha256 digest → success`，推理却输出纯乱码。校验方法：

```powershell
Get-FileHash "…\models\blobs\sha256-<digest>" -Algorithm SHA256
# 对比文件名中的 digest，不匹配即损坏
```

**→ 不要手动改 partial 文件名，中断后删掉重下，或改用 GGUF 导入（推荐）**。

### 9.6 `OLLAMA_HOST` 不支持多地址
写 `127.0.0.1:11434,10.8.0.3:11434` 会导致服务起不来（整串被当成一个地址）。要么绑 `0.0.0.0`，要么只绑单一 IP。

---

## 十、脚本文件

| 文件 | 用途 |
|---|---|
| `scripts/download-ollama.ps1` | 安装包断点续传 + 多镜像切换下载器 |
| `scripts/install-ollama.ps1` | 静默安装 + 校验 + 启动 |
| `scripts/b-client-test.ps1` | 远程电脑连通性/性能一键测试 |
| `dsh/cordis.patch.snippet.yml` | DSH 接入配置片段 |
| `scripts/Modelfile.qwen3-8b` | 8B 导入模板（16K） |
| `scripts/Modelfile.qwen3-30b-a3b` | 30B-A3B 导入模板 |

---

## 许可

MIT
