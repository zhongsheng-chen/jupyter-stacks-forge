# Jupyter Stacks Forge 🔨

<div align="center">

[![GitHub repository](https://img.shields.io/badge/github-zhongsheng--chen%2Fjupyter--stacks--forge-blue?logo=github)](https://github.com/zhongsheng-chen/jupyter-stacks-forge)
[![Docker](https://img.shields.io/badge/docker-20.10%2B-blue?logo=docker)](https://www.docker.com/)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-green?logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**A powerful Jupyter Docker image builder toolkit, based on official Jupyter Docker Stacks**

[English](#english) | [中文](#chinese)

</div>

---

## <a name="chinese"></a>🇨🇳 中文介绍

### 📖 项目简介

`jupyter-stacks-forge` 是一个用于构建 Jupyter Docker 镜像的完整工具集。它提供了多个预配置的 Jupyter 镜像构建脚本，让您可以轻松地创建自定义的 Jupyter 环境。

### ✨ 特性

- 🚀 **一键构建** - 简单的命令行工具，快速构建 Jupyter 镜像
- 🏷️ **灵活命名** - 支持自定义镜像名、标签和所有者
- 📦 **多版本支持** - 提供多个 Python 版本的环境配置
- 🔧 **可定制化** - 支持传递构建参数，自定义基础镜像
- 📝 **详细日志** - 完整的构建日志记录，方便排查问题
- ✅ **自动验证** - 构建完成后自动验证 Jupyter 和 Python
- 📤 **镜像推送** - 支持推送到 Docker Hub 或私有仓库
- 🧹 **自动清理** - 可选的旧镜像清理功能
- 🎨 **美观输出** - 彩色输出和进度显示

### 🏗️ 镜像类型

| 镜像 | 目录 | 描述 |
|------|------|------|
| **foundation** | `foundation/` | 基础系统镜像，包含 conda 和基础工具 |
| **base-notebook** | `base-notebook/` | 基础 Jupyter 镜像，包含 Jupyter 核心组件 |
| **datascience-notebook** | `datascience-notebook/` | 数据科学镜像，包含 Python 数据科学库 |
| **datascience-notebook-multi** | `datascience-notebook-multi/` | 多版本 Python 数据科学镜像 (3.7-3.12) |

### 📋 环境要求

- Docker 20.10+
- Bash 4.0+
- 操作系统：Linux、macOS 或 WSL2

### 🚀 快速开始

#### 1. 克隆仓库

```bash
git clone https://github.com/zhongsheng-chen/jupyter-stacks-forge.git
cd jupyter-stacks-forge
```

#### 2. 构建基础镜像

```bash
# 进入基础镜像目录
cd base-notebook

# 构建默认镜像
./build.sh

# 或者自定义构建
./build.sh --owner zhongsheng --tag python-3.11 --no-cache
```

#### 3. 构建数据科学镜像

```bash
# 构建标准数据科学镜像
cd datascience-notebook
./build.sh

# 构建多版本 Python 数据科学镜像
cd datascience-notebook-multi
./build.sh --tag py3.11 --build-arg PYTHON_VERSION=3.11
```

### 📚 详细用法

#### 基础构建命令

```bash
# 查看帮助
./build.sh --help

# 默认构建 (zhongsheng/base-notebook:latest)
./build.sh

# 自定义标签
./build.sh --tag python-3.11

# 自定义镜像名
./build.sh --image my-notebook

# 自定义所有者
./build.sh --owner myusername
```

#### 组合用法

```bash
# 同时指定镜像名和标签
./build.sh --image data-science --tag 3.9.13

# 指定所有者和镜像名
./build.sh --owner myuser --image custom

# 使用完整镜像名
./build.sh --image myuser/custom-notebook

# 构建并推送到仓库
./build.sh --owner myuser --push
```

#### 高级选项

```bash
# 禁用缓存并显示详细输出
./build.sh --no-cache --verbose

# 指定日志目录
./build.sh --log-dir /var/log/jupyter-builds

# 自定义基础镜像
./build.sh --build-arg BASE_IMAGE=quay.io/jupyter/scipy-notebook

# 自定义基础镜像标签
./build.sh --build-arg BASE_TAG=2025-01

# 构建并推送到私有仓库
./build.sh --registry myregistry.com:5000 --owner team --push
```

### 🏗️ 镜像层级关系

```
foundation (基础系统)
    ↓
base-notebook (Jupyter 基础)
    ↓
datascience-notebook (数据科学)
    ↓
datascience-notebook-multi (多版本 Python)
```

### 📁 项目结构

```
jupyter-stacks-forge/
├── README.md                     # 项目文档
├── .gitignore                    # Git 忽略配置
├── foundation/                    # 基础系统镜像
│   ├── Dockerfile
│   ├── build.sh
│   ├── start.sh
│   ├── fix-permissions
│   └── 10activate-conda-env.sh
├── base-notebook/                 # 基础 Jupyter 镜像
│   ├── Dockerfile
│   ├── build.sh
│   ├── start-notebook.py
│   ├── start-notebook.sh
│   ├── start-singleuser.py
│   ├── start-singleuser.sh
│   ├── jupyter_server_config.py
│   └── docker_healthcheck.py
├── datascience-notebook/          # 数据科学镜像
│   ├── Dockerfile
│   ├── build.sh
│   ├── requirements-core.txt
│   ├── requirements-db.txt
│   └── requirements-ml.txt
└── datascience-notebook-multi/    # 多版本数据科学镜像
    ├── Dockerfile
    ├── build.sh
    └── envs/
        ├── environment-Python3.7.yml
        ├── environment-Python3.8.yml
        ├── environment-Python3.9.yml
        ├── environment-Python3.10.yml
        ├── environment-Python3.11.yml
        └── environment-Python3.12.yml
```

### 🎯 使用场景

#### 场景1：个人开发环境

```bash
cd base-notebook
./build.sh --tag my-dev-env
docker run -p 8888:8888 zhongsheng/base-notebook:my-dev-env
```

#### 场景2：团队共享镜像

```bash
cd datascience-notebook
./build.sh --owner team-name --push
# 团队成员可以直接使用：
docker pull team-name/datascience-notebook:latest
```

#### 场景3：CI/CD 流水线

```bash
# 在 CI 脚本中
cd datascience-notebook-multi
for version in 3.8 3.9 3.10 3.11 3.12; do
    ./build.sh --tag py$version --build-arg PYTHON_VERSION=$version --push
done
```

### 🔧 自定义开发

#### 添加新的 Python 包

```bash
# 编辑 requirements 文件
vim datascience-notebook/requirements-core.txt
# 添加：new-package==1.0.0

# 重新构建
./build.sh --no-cache
```

#### 修改 Conda 环境

```bash
# 编辑环境配置文件
vim datascience-notebook-multi/envs/environment-Python3.11.yml
# 添加新的 conda 包

# 重新构建
./build.sh --tag py3.11-custom
```

### ⚠️ 常见问题

#### Q1: 构建失败，提示权限错误
**A:** 确保 Docker 守护进程正在运行，并且当前用户有权限访问 Docker：
```bash
sudo systemctl start docker
sudo usermod -aG docker $USER
# 重新登录
```

#### Q2: 推送镜像时认证失败
**A:** 先登录 Docker Hub：
```bash
docker login
# 或者使用个人访问令牌
docker login -u zhongsheng-chen --password-stdin < your-token
```

#### Q3: 构建速度慢
**A:** 使用缓存并确保网络稳定：
```bash
# 使用镜像加速器
# 编辑 /etc/docker/daemon.json
{
  "registry-mirrors": ["https://docker.mirrors.ustc.edu.cn"]
}
# 重启 Docker
sudo systemctl restart docker
```

### 📊 构建示例输出

```
════════════════════════════════════════
🚀 Building Jupyter image
════════════════════════════════════════
Base image: jupyter/docker-stacks-foundation:latest
Output image: zhongsheng/base-notebook:latest
Registry: docker.io
Cache: Enabled
Log file: /home/zhongsheng/jupyter-stacks-forge/base-notebook/logs/build_zhongsheng_base-notebook_latest_20260305_223335.log
Start time: 2026-03-05 22:33:35
════════════════════════════════════════

✅ Build completed! 22:33:37
[SUCCESS] 2026-03-05 22:33:37 - Docker build completed successfully

[SUCCESS] 2026-03-05 22:33:37 - Build finished successfully!
[INFO] 2026-03-05 22:33:37 - Verifying image: zhongsheng/base-notebook:latest

🔍 Verifying image...

📓 Checking Jupyter...
[SUCCESS] 2026-03-05 22:33:39 - Jupyter is available
✅ Jupyter OK

🐍 Checking Python...
Python 3.13.12
[SUCCESS] 2026-03-05 22:33:40 - Python is available

📦 Image details:
Size: 950 MB
[INFO] 2026-03-05 22:33:40 - Image size: 950 MB

════════════════════════════════════════
✓ Build Summary
════════════════════════════════════════
Image: zhongsheng/base-notebook:latest
Registry: docker.io
Owner: zhongsheng
ID: cc71000816b1
Size: 950 MB
Created: 2026-03-04
════════════════════════════════════════

[SUCCESS] 2026-03-05 22:33:40 - All done. You can now restart JupyterHub.

📝 Build log saved to: /home/zhongsheng/jupyter-stacks-forge/base-notebook/logs/build_zhongsheng_base-notebook_latest_20260305_223335.log
[INFO] 2026-03-05 22:33:40 - Total build time: 0m 5s
[SUCCESS] 2026-03-05 22:33:40 - Build completed successfully

```

## 删除镜像

- 先删除所有 zhongshengchen 的容器（如果有）
```bash
docker ps -a --filter=name="zhongshengchen/*" -q | xargs -r docker rm -f
```

- 强制删除所有 zhongshengchen 的镜像
```bash
docker images --filter=reference="zhongshengchen/*" -q | sort -u | xargs -r docker rmi -f
```

## 调试脚本
```bash
bash -x ./build.sh 2>&1 | tee output
```

## 静默钩子日志（安静模式）
```bash
docker run --rm -e JUPYTER_DOCKER_STACKS_QUIET=1 -ti zhongsheng/base-notebook:latest /bin/bash
```

### 🤝 贡献指南

欢迎贡献！您可以通过以下方式参与：

1. 🍴 Fork 本仓库
2. 🌿 创建您的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 💾 提交您的修改 (`git commit -m 'Add some AmazingFeature'`)
4. 📤 推送到分支 (`git push origin feature/AmazingFeature`)
5. 🔍 提交 Pull Request

### 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

### 📞 联系方式

- **作者**: zhongsheng-chen
- **GitHub**: [@zhongsheng-chen](https://github.com/zhongsheng-chen)
- **项目链接**: [https://github.com/zhongsheng-chen/jupyter-stacks-forge](https://github.com/zhongsheng-chen/jupyter-stacks-forge)

### 🙏 致谢

- [Jupyter Docker Stacks](https://github.com/jupyter/docker-stacks) - 官方 Jupyter Docker 镜像项目
- 所有贡献者和用户

---

## <a name="english"></a>🇬🇧 English Introduction

### 📖 Project Overview

`jupyter-stacks-forge` is a comprehensive toolkit for building Jupyter Docker images. It provides multiple pre-configured Jupyter image build scripts, allowing you to easily create custom Jupyter environments.

### ✨ Features

- 🚀 **One-click build** - Simple command-line tool for quick Jupyter image building
- 🏷️ **Flexible naming** - Support for custom image names, tags, and owners
- 📦 **Multi-version support** - Multiple Python version environment configurations
- 🔧 **Customizable** - Support for build arguments and custom base images
- 📝 **Detailed logging** - Complete build logs for troubleshooting
- ✅ **Automatic verification** - Auto-verify Jupyter and Python after build
- 📤 **Image push** - Support pushing to Docker Hub or private registry
- 🧹 **Auto cleanup** - Optional old image cleanup
- 🎨 **Beautiful output** - Colorful output and progress display

### 🏗️ Image Types

| Image | Directory | Description |
|-------|-----------|-------------|
| **foundation** | `foundation/` | Base system image with conda and basic tools |
| **base-notebook** | `base-notebook/` | Base Jupyter image with core components |
| **datascience-notebook** | `datascience-notebook/` | Data science image with Python data science libraries |
| **datascience-notebook-multi** | `datascience-notebook-multi/` | Multi-version Python data science images (3.7-3.12) |

For detailed usage instructions, please refer to the [Chinese documentation](#chinese) above.

---

<div align="center">
Made with ❤️ by zhongsheng-chen
</div>
