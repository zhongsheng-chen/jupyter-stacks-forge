# ==========================================
# 自定义 Jupyter 用户镜像（兼容 DockerSpawner）
# 多 Python 版本环境：3.7–3.12
#
# 设计说明：
# - Base Python 固定为 3.10（仅用于 bootstrap）
# - 真实 Python 版本来自 conda envs/*
# - multi 模式：一次构建，多个 kernel
#
# Conda env 命名必须规范：
#   python37 / python38 / python39 / python310 / python311 / python312
# ==========================================

ARG BASE_IMAGE=jupyter/base-notebook
ARG BASE_TAG=python-3.10
FROM ${BASE_IMAGE}:${BASE_TAG}

LABEL maintainer="Zhongsheng Chen <zhongsheng.chen@outlook.com>"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# ==================================================
# 构建参数
# ==================================================
ARG PYTHON_VERSION=multi
ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
ARG PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn
ARG BUILD_TYPE=production  # 可选：development, testing, production
ARG EXTRA_APT_PACKAGES=""
ARG CLEAN_BUILD_DEPS=true

# 数据库客户端安装控制
ARG INSTALL_GAUSSDB=true
ARG INSTALL_VERTICA=true
ARG INSTALL_ORACLE=true
ARG INSTALL_HADOOP=true
ARG INSTALL_ODPS=true

# ==================================================
# 1. 系统依赖
# ==================================================
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc g++ gfortran pkg-config \
        python3-dev \
        libcairo2-dev libgirepository1.0-dev libgraphviz-dev \
        libgomp1 \
        libaio1 \
        unixodbc unixodbc-dev \
        git wget curl tar unzip \
        procps lsof net-tools iputils-ping \
        less vim \
        ca-certificates \
        locales tzdata \
        default-libmysqlclient-dev \
        libpq5 libpq-dev \
        graphviz \
        fonts-noto-cjk \
        ${EXTRA_APT_PACKAGES} \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# ==================================================
# 2. 拷贝依赖文件
# ==================================================
WORKDIR /tmp
COPY requirements-*.txt ./
COPY wheels/ ./wheels/
COPY envs/ ./envs/

# ==================================================
# 3. 创建 Conda Python 环境和 kernel 注册
# ==================================================
RUN set -eux; \
    # 根据构建类型选择 requirements 文件
    if [ "${BUILD_TYPE}" = "development" ]; then \
        EXTRA_REQUIRE="requirements-dev.txt"; \
    elif [ "${BUILD_TYPE}" = "testing" ]; then \
        EXTRA_REQUIRE="requirements-test.txt"; \
    else \
        EXTRA_REQUIRE=""; \
    fi && \
    \
    # 安装基础 Python 依赖
    pip install --upgrade pip && \
    pip install --no-cache-dir -i ${PIP_INDEX_URL} \
        --trusted-host ${PIP_TRUSTED_HOST} \
        -r requirements-core.txt \
        -r requirements-ml.txt \
        -r requirements-db.txt \
        ${EXTRA_REQUIRE} && \
    { pip check || echo "警告：存在 Python 依赖冲突" >&2; } && \
    \
    # 创建 Conda 环境
    if [ "$PYTHON_VERSION" = "multi" ]; then \
        for yml in envs/environment-Python*.yml; do \
            env_name=$(grep '^name:' "$yml" | awk '{print $2}'); \
            echo "▶ Creating conda env: $env_name"; \
            conda env create -f "$yml"; \
        done; \
    else \
        conda env create -f "envs/environment-Python${PYTHON_VERSION}.yml"; \
    fi; \
    \
    # 注册 Jupyter Kernel
    if [ "$PYTHON_VERSION" = "multi" ]; then \
        for yml in envs/environment-Python*.yml; do \
            env_name=$(grep '^name:' "$yml" | awk '{print $2}'); \
            py="/opt/conda/envs/$env_name/bin/python"; \
            if [ -x "$py" ]; then \
                pretty_ver=$(echo "$env_name" | sed 's/python//' | sed 's/\([0-9]\)\([0-9]\+\)/\1.\2/'); \
                echo "▶ Registering kernel: Python $pretty_ver"; \
                "$py" -m ipykernel install \
                    --user \
                    --name "$env_name" \
                    --display-name "Python $pretty_ver"; \
            else \
                echo "⚠️ Skip kernel $env_name (python not found)"; \
            fi; \
        done; \
    else \
        yml="envs/environment-Python${PYTHON_VERSION}.yml"; \
        env_name=$(grep '^name:' "$yml" | awk '{print $2}'); \
        py="/opt/conda/envs/$env_name/bin/python"; \
        echo "▶ Registering kernel: Python $PYTHON_VERSION"; \
        "$py" -m ipykernel install \
            --user \
            --name "$env_name" \
            --display-name "Python $PYTHON_VERSION"; \
    fi; \
    \
    # 清理 Conda 缓存
    conda clean -afy && \
    rm -rf /opt/conda/pkgs /root/.cache /home/jovyan/.cache

# ==================================================
# 4. 锁死 base env（禁止 pip / conda install）
# ==================================================
RUN chmod -R a-w /opt/conda/lib/python3.10/site-packages \
 && chmod -R a-w /opt/conda/bin

# ==================================================
# 5. 清理 build 依赖
# ==================================================
RUN if [ "${CLEAN_BUILD_DEPS}" = "true" ]; then \
        apt-get purge -y \
            build-essential gcc g++ gfortran pkg-config \
            python3-dev \
            libcairo2-dev libgirepository1.0-dev libgraphviz-dev \
        && apt-get autoremove -y \
        && apt-get clean; \
    fi && \
    rm -rf /var/lib/apt/lists/* /tmp/wheels /tmp/requirements-*.txt /tmp/envs

# ==================================================
# 6. 安装数据库客户端（条件安装）
# ==================================================
# 复制客户端文件
COPY db_clients/ /tmp/db_clients/

# 安装客户端
RUN set -eux; \
    \
    # 创建必要的目录（条件创建）
    if [ "${INSTALL_GAUSSDB}" = "true" ]; then \
        mkdir -p /opt/gaussdb; \
    fi; \
    if [ "${INSTALL_VERTICA}" = "true" ]; then \
        mkdir -p /opt/vertica; \
    fi; \
    if [ "${INSTALL_ORACLE}" = "true" ]; then \
        mkdir -p /opt/oracle; \
    fi; \
    if [ "${INSTALL_HADOOP}" = "true" ]; then \
        mkdir -p /opt/hadoopclient; \
    fi; \
    \
    # 安装 GaussDB 客户端
    if [ "${INSTALL_GAUSSDB}" = "true" ] && [ -f /tmp/db_clients/gaussdb.tar.gz ]; then \
        echo "Installing GaussDB client..." && \
        tar -xzf /tmp/db_clients/gaussdb.tar.gz -C /opt/gaussdb && \
        if [ -f /opt/gaussdb/bin/gsql ]; then \
            echo "  - GaussDB client: ✅ Installed (gsql)"; \
        else \
            echo "  - GaussDB client: ⚠️ 未正确安装"; \
        fi; \
    fi; \
    \
    # 安装 Vertica 客户端
    if [ "${INSTALL_VERTICA}" = "true" ] && [ -f /tmp/db_clients/vertica-client-12.0.4-0.x86_64.tar.gz ]; then \
        echo "Installing Vertica client..." && \
        tar -xzf /tmp/db_clients/vertica-client-12.0.4-0.x86_64.tar.gz -C /opt/vertica && \
        if [ -f /opt/vertica/bin/vsql ]; then \
            echo "  - Vertica client: ✅ Installed (vsql)"; \
        else \
            echo "  - Vertica client: ⚠️ 未正确安装"; \
        fi; \
    fi; \
    \
    # 安装 Oracle 客户端
    if [ "${INSTALL_ORACLE}" = "true" ] && [ -f /tmp/db_clients/oracleinstantclient.tar.gz ]; then \
        echo "Installing Oracle client..." && \
        tar -xzf /tmp/db_clients/oracleinstantclient.tar.gz -C /opt/oracle && \
        \
        # 查找 libclntsh.so 文件
        oracle_lib=$(find /opt/oracle -name "libclntsh.so*" -type f | head -1) && \
        if [ -n "${oracle_lib}" ]; then \
            # 创建标准名称的符号链接
            ln -sf "${oracle_lib}" /usr/lib/libclntsh.so; \
            # 也在 Oracle 目录中创建符号链接
            if [ ! -f /opt/oracle/libclntsh.so ]; then \
                ln -sf "${oracle_lib}" /opt/oracle/libclntsh.so; \
            fi; \
            \
            # 查找并链接其他可能的库文件
            for lib in libclntshcore.so libocci.so; do \
                lib_file=$(find /opt/oracle -name "${lib}*" -type f | head -1); \
                if [ -n "${lib_file}" ]; then \
                    ln -sf "${lib_file}" "/usr/lib/${lib}" 2>/dev/null || true; \
                fi; \
            done; \
            \
            # 检测组件
            components=1; \
            [ -f /opt/oracle/libocci.so* ] && components=$((components + 1)); \
            [ -f /opt/oracle/sqlplus ] && components=$((components + 1)); \
            [ -f /opt/oracle/adrci ] && components=$((components + 1)); \
            \
            echo "  - Oracle client: ✅ Installed ($components components)"; \
            \
            # 查找并链接 sqlplus（如果存在）
            if [ -f /opt/oracle/sqlplus ]; then \
                ln -sf /opt/oracle/sqlplus /usr/local/bin/sqlplus; \
                echo "    • sqlplus: available"; \
            fi; \
            \
            # 显示其他有用信息
            if [ -f /opt/oracle/adrci ]; then \
                echo "    • adrci: available (diagnostic tool)"; \
            fi; \
        else \
            echo "  - Oracle client: ⚠️ 未正确安装"; \
            echo "    目录内容:"; \
            ls -la /opt/oracle | head -20 | sed 's/^/      /'; \
        fi; \
    fi; \
    \
    # 安装 Hadoop 客户端
    if [ "${INSTALL_HADOOP}" = "true" ] && [ -f /tmp/db_clients/hadoopclient.tar.gz ]; then \
        echo "Installing Hadoop client..." && \
        tar -xzf /tmp/db_clients/hadoopclient.tar.gz -C /opt/hadoopclient && \
        # 检测 Hadoop 组件
        components=0; \
        if [ -f /opt/hadoopclient/bin/hadoop ]; then \
            echo "  - Hadoop core: ✅ Installed"; \
            components=$((components + 1)); \
        fi; \
        if [ -d /opt/hadoopclient/Hive ] && [ -f /opt/hadoopclient/Hive/Beeline/bin/hive ]; then \
            echo "  - Hive: ✅ Installed"; \
            components=$((components + 1)); \
        elif [ -d /opt/hadoopclient/Hive ]; then \
            echo "  - Hive: ⚠️ 可能未完整安装 (目录存在但缺少可执行文件)"; \
        fi; \
        if [ -d /opt/hadoopclient/HBase ] && [ -f /opt/hadoopclient/HBase/hbase/bin/hbase ]; then \
            echo "  - HBase: ✅ Installed"; \
            components=$((components + 1)); \
        elif [ -d /opt/hadoopclient/HBase ]; then \
            echo "  - HBase: ⚠️ 可能未完整安装"; \
        fi; \
        if [ -d /opt/hadoopclient/Spark ] && [ -f /opt/hadoopclient/Spark/spark/bin/spark-shell ]; then \
            echo "  - Spark: ✅ Installed"; \
            components=$((components + 1)); \
        elif [ -d /opt/hadoopclient/Spark ]; then \
            echo "  - Spark: ⚠️ 可能未完整安装"; \
        fi; \
        if [ $components -eq 0 ]; then \
            echo "  - Hadoop client: ⚠️ 未检测到任何组件"; \
        fi; \
    fi; \
    \
    # 清理临时文件
    rm -rf /tmp/db_clients

# 设置环境变量
ENV GAUSSHOME=/opt/gaussdb
ENV VERTICA_HOME=/opt/vertica
ENV ORACLE_HOME=/opt/oracle
ENV ODPS_HOME=/opt/odpscmd
ENV HIVE_HOME=/opt/hadoopclient/Hive  
ENV HADOOP_HOME=/opt/hadoopclient/HDFS/hadoop
ENV HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop

# 设置 PATH 和 LD_LIBRARY_PATH（条件设置）
ENV PATH="${INSTALL_GAUSSDB:+${GAUSSHOME}/bin:}${INSTALL_VERTICA:+${VERTICA_HOME}/bin:}${INSTALL_ODPS:+${ODPS_HOME}/bin:}${INSTALL_HADOOP:+${HADOOP_HOME}/bin:}${INSTALL_HADOOP:+${HIVE_HOME}/bin:}${PATH}"
ENV LD_LIBRARY_PATH="${INSTALL_ORACLE:+${ORACLE_HOME}:}${INSTALL_GAUSSDB:+${GAUSSHOME}/lib:}${INSTALL_VERTICA:+${VERTICA_HOME}/lib}"

# ==================================================
# 7. matplotlib 全局中文配置
# ==================================================
RUN mkdir -p /usr/local/etc && \
    cat << 'EOF' > /usr/local/etc/matplotlibrc
font.family         : sans-serif
font.sans-serif     : Noto Sans CJK SC
axes.unicode_minus  : False
EOF

# ==================================================
# 8. pip 行为收紧（base env 不可污染）
# ==================================================
RUN mkdir -p /etc/pip && \
    cat << 'EOF' > /etc/pip.conf
[global]
user = true
disable-pip-version-check = true
no-warn-script-location = true
EOF

RUN mkdir -p /etc/profile.d && \
    cat << 'EOF' > /etc/profile.d/pip-warning.sh
if [[ "$CONDA_DEFAULT_ENV" == "base" ]]; then
  echo "⚠️  Base conda env is read-only."
  echo "👉 Please switch Jupyter kernel before pip install."
fi
EOF

# ==================================================
# 9. 数据库客户端初始化
# ==================================================
RUN mkdir -p /usr/local/bin/start-notebook.d && \
    cat << 'EOF' > /usr/local/bin/start-notebook.d/10-db-client-init.sh
#!/usr/bin/env bash
set -e
umask 077
HOME_DIR="${HOME}"

echo "🔍 初始化数据库客户端配置..."

# 创建必要的配置目录
mkdir -p "${HOME_DIR}/.odps"

# 检测已安装的客户端
GAUSSDB_INSTALLED=false
VERTICA_INSTALLED=false
ORACLE_INSTALLED=false
HADOOP_INSTALLED=false

# 检查 GaussDB
if command -v gsql &> /dev/null; then
    GAUSSDB_INSTALLED=true
    echo "✅ GaussDB client detected: $(gsql --version 2>/dev/null | head -1)"
fi

# 检查 Vertica
if command -v vsql &> /dev/null; then
    VERTICA_INSTALLED=true
    echo "✅ Vertica client detected: $(vsql --version 2>/dev/null | head -1)"
fi

# 检查 Oracle
if [ -n "${ORACLE_HOME}" ] && [ -f "${ORACLE_HOME}/libclntsh.so" ]; then
    ORACLE_INSTALLED=true
    echo "✅ Oracle client detected"
fi

# 检查 Hadoop
if [ -n "${HADOOP_HOME}" ] && [ -d "${HADOOP_HOME}/bin" ]; then
    HADOOP_INSTALLED=true
    echo "✅ Hadoop client detected"
fi

# 配置 .pgpass（只对已安装的客户端添加配置）
PGPASS="${HOME_DIR}/.pgpass"
: > "${PGPASS}"

# 只有 GaussDB 已安装时才添加其配置
if [ "$GAUSSDB_INSTALLED" = "true" ] && [[ -n "${GAUSSDB_HOST}" && -n "${GAUSSDB_PASSWORD}" ]]; then
    echo "📝 Adding GaussDB connection to .pgpass"
    echo "${GAUSSDB_HOST}:${GAUSSDB_PORT:-5432}:${GAUSSDB_DBNAME:-postgres}:${GAUSSDB_USER:-${USER}}:${GAUSSDB_PASSWORD}" >> "${PGPASS}"
fi

# 只有 Vertica 已安装时才添加其配置
if [ "$VERTICA_INSTALLED" = "true" ] && [[ -n "${VERTICA_HOST}" && -n "${VERTICA_PASSWORD}" ]]; then
    echo "📝 Adding Vertica connection to .pgpass"
    echo "${VERTICA_HOST}:${VERTICA_PORT:-5433}:${VERTICA_DBNAME:-${VERTICA_USER:-dbadmin}}:${VERTICA_USER:-dbadmin}:${VERTICA_PASSWORD}" >> "${PGPASS}"
fi

# 只在有内容时才设置权限
if [[ -s "${PGPASS}" ]]; then
    chmod 600 "${PGPASS}"
    echo "✅ Created .pgpass with database credentials"
else
    rm -f "${PGPASS}"  # 删除空文件
fi

# 只为已安装的客户端创建配置文件
if [ "$GAUSSDB_INSTALLED" = "true" ] || [ "$VERTICA_INSTALLED" = "true" ]; then
    # psql / gsql 配置
    cat << 'EORC' > "${HOME_DIR}/.psqlrc"
-- psql / gsql 通用配置
\set PROMPT1 '%n@%M:%> %/%R%# '
\set HISTSIZE 10000
\set VERBOSITY verbose
\timing on
EORC

    # 如果 GaussDB 安装了，复制配置到 .gsqlrc
    if [ "$GAUSSDB_INSTALLED" = "true" ]; then
        cp "${HOME_DIR}/.psqlrc" "${HOME_DIR}/.gsqlrc"
        echo "✅ Created .gsqlrc for GaussDB"
    fi
    echo "✅ Created .psqlrc for PostgreSQL clients"
fi

# 只为 Vertica 创建配置
if [ "$VERTICA_INSTALLED" = "true" ]; then
    cat << 'EORC' > "${HOME_DIR}/.vsqlrc"
-- vsql 交互配置
\set PROMPT1 '%n@%h:%p %d=> '
\timing
EORC
    echo "✅ Created .vsqlrc for Vertica"
fi

# 设置配置文件权限
chmod 600 "${HOME_DIR}/.psqlrc" "${HOME_DIR}/.gsqlrc" "${HOME_DIR}/.vsqlrc" 2>/dev/null || true

# 显示最终状态
echo "📊 数据库客户端配置状态:"
echo "  - GaussDB: $([ "$GAUSSDB_INSTALLED" = "true" ] && echo "已安装 ✓" || echo "未安装 ✗")"
echo "  - Vertica: $([ "$VERTICA_INSTALLED" = "true" ] && echo "已安装 ✓" || echo "未安装 ✗")"
echo "  - Oracle: $([ "$ORACLE_INSTALLED" = "true" ] && echo "已安装 ✓" || echo "未安装 ✗")"
echo "  - Hadoop: $([ "$HADOOP_INSTALLED" = "true" ] && echo "已安装 ✓" || echo "未安装 ✗")"

echo "✅ 数据库客户端初始化完成"
EOF

RUN chmod +x /usr/local/bin/start-notebook.d/10-db-client-init.sh

# ==================================================
# 10. 全局分页器 less 配置
# ==================================================
RUN mkdir -p /etc/profile.d && \
    cat << 'EOF' > /etc/profile.d/pager.sh
export PAGER=less
export LESS='-RS'
EOF

# ==================================================
# 11. 修复 HOME / 挂载卷权限
# ==================================================
RUN fix-permissions "${HOME}"

# ==================================================
# 12. 健康检查
# ==================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ["jupyter", "notebook", "list"] || exit 1

# ==================================================
# 13. 显示构建信息
# ==================================================
RUN echo "Build completed: PYTHON_VERSION=${PYTHON_VERSION}, BUILD_TYPE=${BUILD_TYPE}, PIP_INDEX_URL=${PIP_INDEX_URL}"

# ==================================================
# 14. 切回 jovyan 用户
# ==================================================
USER ${NB_UID}
WORKDIR "${HOME}"

CMD ["start-notebook.sh"]