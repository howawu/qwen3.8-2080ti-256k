# RTX 2080 Ti 上的 Qwen3.8-27B 终极部署

## 2018 老卡 · 256K 上下文 · 67 tok/s · Q4_K_M 级体验

[English](README.md)

这套方案把魔改 22 GB RTX 2080 Ti 基本压榨到极限：单卡同时运行现代 27B 混合模型、1.9B DFlash2 草稿模型、256K 逻辑上下文和多模态支持。

**这是目前我们所知单张 22 GB RTX 2080 Ti 上最激进、也最均衡的 Qwen3.8 部署。** 它不是牺牲速度换上下文，也不是牺牲质量刷速度，而是把三者放进同一套日常可用配置。

> **RTX 2080 Ti 22 GB · 256K 上下文 · 简单任务 67 tok/s · 日常 45–48 tok/s · DFlash2 + n-gram 重复上下文白捡加速**

![鹈鹕骑自行车动画测试](assets/pelican-bike.gif)

## 方案优势

- **老卡跑现代 27B 模型**：针对 `sm_75` 构建，并为宽投机验证批次启用 Turing MMVQ→MMQ 路由。
- **256K 逻辑上下文**：目标 KV 在 GPU 上保留 112,640 tokens 物理工作集，其余历史由 KVMem 检索；不是把 256K KV 全塞进显存。
- **速度与长上下文兼顾**：简单代码任务六次冷提示中位数 66.92 tok/s；MATLAB Kalman 实际任务 44.87 tok/s；日常交互约 45–48 tok/s。
- **DFlash2 + n-gram 双投机**：新内容由 DFlash2 起草；代码、模板、日志、文档改写和历史对话中的重复片段由 `ngram-mod` 直接查表起草。
- **重复上下文近乎“白捡”**：同一代码请求的演示中，首轮 70.39 tok/s，后续 n-gram 命中中位数 227.65 tok/s，提升 3.23×。目标模型仍要验证候选，因此不是零计算，而是命中时省掉神经网络草稿推理。
- **低比特但优先保质量**：这套混合 Q2 配方的主观使用质量接近 Q4_K_M，同时腾出了草稿模型和长上下文缓存空间；这是使用评价，不是困惑度等价声明。
- **减少无效过度思考**：EfficientThink/SimPO 模型配方结合 `reasoning-effort=low`，不是简单粗暴地全局关闭思考。
- **跨请求前缀复用**：修复生成起点 checkpoint 后，11K-token 后续请求由 21.7 s 降到 0.356 s。

## 两种运行模式，同一张卡

仓库给出**两套启动配置**，都监听 `127.0.0.1:8080`、都用同一批模型文件。22 GB 显存一次只装得下一套，所以让两者共用端口——无论当前跑的是哪一套，客户端、代理和 IDE 集成都不用改配置。

| 模式 | 引擎 | 上下文 | 启动脚本 | 定位 |
|---|---|---:|---|---|
| **A** | 上游 llama.cpp + DFlash2 | 131,072 | [`scripts/start-llama.ps1`](scripts/start-llama.ps1) | 日常主力：单 token 延迟最低、显存余量最大 |
| **B** | KVMem | 262,144（逻辑） | [`scripts/start-kvmem.ps1`](scripts/start-kvmem.ps1) | 长上下文模式：112,640 tokens 物理工作集，旧历史走检索 |

每个命令行开关、每个环境变量、每一项显存占用和已知的坑，都写在 **[docs/LAUNCH_PARAMS.md](docs/LAUNCH_PARAMS.md)** 里，其中包含最容易导致复现失败的十一个环节。

## 实测范围

**模式 A（llama.cpp + DFlash2，128K），代码提示词，`temp=0`：**

| 任务 | 结果 |
|---|---:|
| 短上下文解码 | **64.7 tok/s** |
| 125K 上下文解码 | **30.8 tok/s** |
| prefill | 361–380 tok/s |
| Turing 验证路由（MATLAB 任务） | 35.72 → **44.87 tok/s** |

**模式 B（KVMem，256K 逻辑）：**

| 任务 | 结果 |
|---|---:|
| 简单代码生成，六个独立冷提示 | **66.92 tok/s 中位数**（56.35–74.98） |
| MATLAB Kalman 实际任务 | **44.87 tok/s** |
| 日常交互 | **约 45–48 tok/s**，取决于内容和草稿接受率 |
| 同一代码请求、n-gram 热状态 | **227.65 tok/s 中位数**，较首轮 3.23× |
| 命中 11K-token 前缀的后续 prefill | **0.356 s**，较故障基线 61× |

数字属于产出它的那套模式，两者不可互换。完整口径见 [docs/BENCHMARKS.md](docs/BENCHMARKS.md)。

## 显存占用

```text
                          模式 A（128K）        模式 B（256K 逻辑）
目标权重                    12.11 GiB            12.11 GiB
草稿权重                     1.06 GiB             1.06 GiB
目标 KV                 q8_0/q8_0 @128K      112,640 tokens 池，3.65 GiB
草稿 KV                   小，f16            262,144 × 10.6 KiB，2.60 GiB
必须保留的空闲余量          ≥ 0.8 GiB            ≥ 0.8 GiB
```

256K 是**逻辑上下文容量**，不是 256K 目标 KV 全驻留显存。

## 需要下载什么

仓库不包含权重和二进制。三份文件都来自同一个 GGUF 发布，即
[`nerkyor/Qwen3.8-27B-EfficientThink-Uncensored-K3-Opus5-Grok4.6-GPT5.6Sol-SFT-SimPO-DFlash2-GGUF`](https://huggingface.co/nerkyor/Qwen3.8-27B-EfficientThink-Uncensored-K3-Opus5-Grok4.6-GPT5.6Sol-SFT-SimPO-DFlash2-GGUF)
的 **`Q2-LynnStyle`** 目录：

| 文件 | 角色 | SHA256（前 16 位） |
|---|---|---:|
| `Qwen3.8-27B-EfficientThink-SimPO-Q2-LynnStyle.gguf` | 目标模型（12.11 GiB） | `8a84f7ef93b01c63` |
| `dflash2-qwen38-27b-Q4_K_M.gguf` | DFlash2 草稿模型（1.06 GiB） | `e83676f81b660433` |
| `mmproj-Qwen3.8-27B-Q4_K_M.gguf` | 视觉投影，可选（0.50 GiB） | `0d22c439a59fb0ff` |

还有一份非模型文件对复现同样关键：来自
[`froggeric/Qwen-Fixed-Chat-Templates`](https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates)（v22 代）的聊天模板——`reasoning_effort` 正是由它实现的。

**[docs/MODELS.md](docs/MODELS.md)** 给出完整文件清单、字节数、完整校验和、`hf download` 命令、决定调参走向的 manifest 事实（`IQ3_S`/`IQ4_XS` 混合量化构成、目标模型为 text-only/无 MTP 头）以及许可证说明。

## 快速开始

前置条件：

- Windows 11
- 22 GB 显存的 NVIDIA Turing 显卡（在 RTX 2080 Ti 22 GB 上验证）
- 模式 A：llama.cpp `16378d9` 构建出的 `llama-server.exe`，并应用 [Turing 路由补丁](patches/turing-mmvq-mmq-routing.diff)
- 模式 B：按 `75-real` 构建的兼容 `llama-kvmem-server.exe`
- 目标 GGUF、DFlash2 草稿模型、可选 mmproj 和聊天模板

```powershell
Copy-Item .\config.example.ps1 .\config.ps1
notepad .\config.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\check-config.ps1

# 模式 A：128K，上游 llama.cpp + DFlash2
powershell -ExecutionPolicy Bypass -File .\scripts\start-llama.ps1

# 模式 B：256K 逻辑上下文，KVMem
powershell -ExecutionPolicy Bypass -File .\scripts\start-kvmem.ps1
```

再次运行同一启动脚本会停止它启动的服务；若端口被其他程序占用，它只报错，不会静默杀掉用户正在使用的服务。

## 核心参数

**模式 A —— 128K 日常主力：**

```text
--ctx-size 131072 --parallel 1
--n-gpu-layers all --fit off
--flash-attn on
--cache-type-k q8_0 --cache-type-v q8_0
--spec-type draft-dflash,ngram-mod
--spec-draft-n-max 6
--spec-draft-type-k f16 --spec-draft-type-v f16
--mmproj ... --mmproj-device none --no-mmproj-offload
--reasoning on --reasoning-effort low
--temp 0.7 --top-k 20 --top-p 0.8
-b 1024 -ub 512 --threads 8 --threads-batch 8
GGML_MMVQ_MAX=4
GGML_MMVQ_ALL=1
```

**模式 B —— 256K 逻辑上下文：**

```text
-c 262144
--kvmem-method retrieval
--kvmem-budget 96256
--kvmem-gen-reserve 16384
--kv-dtype q8_0
--spec-type draft-dflash,ngram-mod
--spec-draft-n-max 6
-b 1024 -ub 512
GGML_MMVQ_MAX=4
GGML_MMVQ_ALL=1
```

## 鹈鹕骑自行车测试

该测试要求本地模型“生成一个鹈鹕骑自行车的 SVG 动画”。模型输出动画代码，GIF 是渲染结果，包含双腿蹬踏、车轮与曲柄旋转、背景滚动。它展示的是创意编码和指令遵循能力，不是模型直接生成视频像素。详见 [assets/pelican-bike.md](assets/pelican-bike.md)。

## 边界

- 256K 是逻辑上下文，不是 256K 目标 KV 全驻留显存。
- 两套运行模式的数字分别测量，不可混用。
- n-gram 高速数据只代表重复上下文命中，不代表全新文本的通用速度；它用**重复提示词**测得，同一提示连发会让查找表跨请求存活并虚高，基准测试请用独立冷提示。
- “接近 Q4_K_M”和“减少过度思考”是使用评价，不冒充标准化质量 benchmark。
- KVMem 外层仓库目前没有声明许可证，因此本仓库只发布原创部署脚本、配置和数据，不转发其源码或累计衍生补丁；`patches/` 中的 Turing 路由补丁是我们对 MIT 许可的 llama.cpp 的自行改动，在此一并发布。实现清单见 [docs/ENGINE_NOTES.md](docs/ENGINE_NOTES.md)。

## 许可证

本仓库原创脚本和文档采用 MIT；第三方引擎、模型和投影文件各自遵循原许可证，见 [THIRD_PARTY.md](THIRD_PARTY.md)。
