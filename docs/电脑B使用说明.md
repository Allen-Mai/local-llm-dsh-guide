# 电脑B 使用说明（调用电脑A 的本地大模型）

> 本说明面向「电脑B」的使用者。电脑A 已部署 Ollama 本地大模型，电脑B 只需连上 OpenVPN，即可通过 OpenAI 兼容接口远程调用，无需自己安装任何模型。

---

## 一、前提条件

1. **连上 OpenVPN**（与电脑A 同一个 VPN 网络）。
2. 能 ping 通电脑A 的 VPN 地址 `10.8.0.3`：

   ```powershell
   ping 10.8.0.3
   ```

   如果 ping 不通，先检查 OpenVPN 是否连接；仍不通则联系电脑A 的管理员排查 VPS 的 client-to-client（客户端互访）设置。

---

## 二、快速验证链路

浏览器打开以下地址，**能返回一串 JSON 就说明链路通了**：

```
http://10.8.0.3:11434/api/tags
```

或用命令行测试对话：

```powershell
curl.exe http://10.8.0.3:11434/v1/chat/completions `
  -H "Content-Type: application/json" `
  -d "{\"model\":\"qwen3-8b\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}"
```

> 本仓库附带的 `scripts/b-client-test.ps1` 是一键测试脚本，在电脑B 上运行即可自动完成 ping、API、对话、速度五项检查。

---

## 三、客户端配置（任选其一）

统一参数：

| 参数 | 值 |
|---|---|
| 接口地址（Base URL） | `http://10.8.0.3:11434/v1` |
| API Key | **随便填一个非空字符串**（本地服务无鉴权） |
| 模型名 | 见[第四节](#四模型选择) |

### 方式 1：Cherry Studio（免费、中文，最推荐）

1. 安装 Cherry Studio（cherry-ai.com，Windows/macOS 均可）。
2. 左下角「设置」→「模型服务」→「添加」。
3. 提供商选 **Ollama** 或 **OpenAI**（兼容）。
4. API 地址 / 接口地址填 `http://10.8.0.3:11434`（Cherry Studio 会自动补 `/v1`）。
5. 保存后，在对话界面顶部选择「qwen3-30b-a3b」或「qwen3-8b」即可开始对话。

### 方式 2：Chatbox

1. 设置 → 模型提供方 → 添加自定义提供方。
2. 类型选 OpenAI API 兼容。
3. API 域名填 `http://10.8.0.3:11434/v1`，API Key 随便填。
4. 模型名手动填 `qwen3-30b-a3b` 等。

### 方式 3：Cline / Roo Code（VS Code 插件，适合写代码/Agent）

1. 打开 VS Code → 安装 Cline 或 Roo Code。
2. 打开插件设置 → API Provider 选 **OpenAI Compatible**。
3. Base URL 填 `http://10.8.0.3:11434/v1`，API Key 随便填。
4. Model ID 填 `qwen3-30b-a3b`（Agent 场景首选）。

### 方式 4：任意 OpenAI SDK / 脚本

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://10.8.0.3:11434/v1",
    api_key="sk-任意非空字符串",   # 本地服务不校验
)
resp = client.chat.completions.create(
    model="qwen3-30b-a3b",
    messages=[{"role": "user", "content": "你好"}],
)
print(resp.choices[0].message.content)
```

---

## 四、模型选择

| 模型名 | 上下文 | 速度 | 适用场景 |
|---|---|---|---|
| `qwen3-30b-a3b` | 16K | 37 tok/s | 质量最高，Agent / 复杂推理首选 |
| `qwen3-8b` | 16K | 60 tok/s | 最快，日常问答 |
| `qwen3-8b-long` | 32K | 28 tok/s | 长文档、大代码库 |

---

## 五、常见问题

**Q1：第一次调用要等很久？**
正常。大模型从磁盘加载到显存需要 5–15 秒，加载完成后连续对话就是秒回。

**Q2：模型一直加载不出来 / 超时？**
可能是电脑A 休眠或 Ollama 服务停了。联系管理员确认电脑A 处于开机、不睡眠状态。

**Q3：浏览器能打开 `/api/tags`，但客户端连不上？**
检查客户端 Base URL 是否正确带了 `/v1`，以及是否选了正确的模型名（区分 `qwen3-8b` 和 `qwen3-8b-long`）。

**Q4：能不能用手机？**
能，手机装 Cherry Studio（App），API 地址同样填 `http://10.8.0.3:11434`，前提是手机也连上了同一个 OpenVPN。

**Q5：回答质量时好时坏？**
8B 模型能力有限，复杂任务请切换到 `qwen3-30b-a3b`。

---

## 六、安全提示

- 本地服务目前**无鉴权**，任何连上该 VPN 的设备都能调用电脑A 的显卡算力。请勿把 VPN 接入分享给不信任的人。
- 如需长期多人使用，建议管理员加一层反向代理 + API Key 鉴权。
