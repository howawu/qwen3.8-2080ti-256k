# RTX 2080 Ti 22 GB 上的 256K 本地大模型

[English](README.md)

这是一个面向老 Turing 显卡的本地部署配方：在单张魔改 22 GB RTX 2080 Ti 上同时容纳 27B 目标模型、1.9B DFlash2 草稿模型和 256K 逻辑上下文。

> **RTX 2080 Ti 22 GB · 256K 逻辑上下文 · 简单任务约 67 tok/s · 日常约 45–48 tok/s · DFlash2 + n-gram**

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

## 实测范围

| 任务 | 结果 |
|---|---:|
| 简单代码生成，六个独立冷提示 | **66.92 tok/s 中位数**（56.35–74.98） |
| MATLAB Kalman 实际任务 | **44.87 tok/s** |
| 日常交互 | **约 45–48 tok/s**，取决于内容和草稿接受率 |
| 同一代码请求、n-gram 热状态 | **227.65 tok/s 中位数**，较首轮 3.23× |
| 命中 11K-token 前缀的后续 prefill | **0.356 s**，较故障基线 61× |

完整口径见 [docs/BENCHMARKS.md](docs/BENCHMARKS.md)。

## 快速开始

仓库不包含模型和二进制。准备兼容的 `llama-kvmem-server.exe`、目标 GGUF、DFlash2 草稿模型、可选 mmproj 和聊天模板后：

```powershell
Copy-Item .\config.example.ps1 .\config.ps1
notepad .\config.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\check-config.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\start-kvmem.ps1
```

再次运行启动脚本会停止本仓库启动的 KVMem 服务；若端口被其他程序占用，它只报错，不会静默杀掉用户正在使用的服务。

## 核心参数

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
- n-gram 高速数据只代表重复上下文命中，不代表全新文本的通用速度。
- “接近 Q4_K_M”和“减少过度思考”是使用评价，不冒充标准化质量 benchmark。
- KVMem 外层仓库目前没有声明许可证，因此本仓库只发布原创部署脚本、配置和数据，不转发其源码或累计衍生补丁。实现清单见 [docs/ENGINE_NOTES.md](docs/ENGINE_NOTES.md)。

## 许可证

本仓库原创脚本和文档采用 MIT；第三方引擎、模型和投影文件各自遵循原许可证，见 [THIRD_PARTY.md](THIRD_PARTY.md)。
