# ==========================================
# 构建 Jupyter 镜像
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
        openjdk-11-jre-headless \
        fonts-noto-cjk \
        ${EXTRA_APT_PACKAGES} \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# ==================================================
# 2. Python 依赖
# ==================================================
WORKDIR /tmp

COPY requirements-*.txt ./
COPY wheels/ ./wheels/

# 根据构建类型选择 requirements 文件
RUN if [ "${BUILD_TYPE}" = "development" ]; then \
        EXTRA_REQUIRE="requirements-dev.txt"; \
    elif [ "${BUILD_TYPE}" = "testing" ]; then \
        EXTRA_REQUIRE="requirements-test.txt"; \
    else \
        EXTRA_REQUIRE=""; \
    fi && \
    pip install --upgrade pip && \
    pip install --no-cache-dir -i ${PIP_INDEX_URL} \
        --trusted-host ${PIP_TRUSTED_HOST} \
        -r requirements-core.txt \
        -r requirements-ml.txt \
        -r requirements-db.txt \
        ${EXTRA_REQUIRE} && \
    pip install --no-cache-dir --no-index --find-links=/tmp/wheels datasource oss-storage-utils && \
    { pip check || echo "警告：存在 Python 依赖冲突" >&2; } && \
    rm -rf /tmp/wheels /tmp/requirements-*.txt

# ==================================================
# 2.1 清理 build 依赖
# ==================================================
RUN if [ "${CLEAN_BUILD_DEPS}" = "true" ]; then \
        apt-get purge -y \
            build-essential gcc g++ gfortran pkg-config \
            python3-dev \
            libcairo2-dev libgirepository1.0-dev libgraphviz-dev \
        && apt-get autoremove -y \
        && apt-get clean; \
    fi && \
    rm -rf /var/lib/apt/lists/*

# ==================================================
# 3. 安装数据库客户端（条件安装）
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
    if [ "${INSTALL_ODPS}" = "true" ]; then \
        mkdir -p /opt/odpscmd; \
    fi; \
    \
    # 安装 GaussDB 客户端
    if [ "${INSTALL_GAUSSDB}" = "true" ] && [ -f /tmp/db_clients/gaussdb.tar.gz ]; then \
        echo "Installing GaussDB client..." && \
        tar -xzf /tmp/db_clients/gaussdb.tar.gz -C /opt/gaussdb && \
        if [ -f /opt/gaussdb/bin/gsql ]; then \
            echo "  - GaussDB client: ✅ Installed (gsql)"; \
        else \
            echo "  - GaussDB client: ⚠️ Not installed"; \
        fi; \
    fi; \
    \
    # 安装 Vertica 客户端
    if [ "${INSTALL_VERTICA}" = "true" ] && [ -f /tmp/db_clients/vertica.tar.gz ]; then \
        echo "Installing Vertica client..." && \
        tar -xzf /tmp/db_clients/vertica.tar.gz -C /opt/vertica && \
        if [ -f /opt/vertica/bin/vsql ]; then \
            echo "  - Vertica client: ✅ Installed (vsql)"; \
        else \
            echo "  - Vertica client: ⚠️ Not installed"; \
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
            # 更新动态链接器缓存
            echo "/opt/oracle" > /etc/ld.so.conf.d/oracle.conf && \
            ldconfig; \
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
            echo "  - Oracle client: ⚠️ Not installed"; \
            echo "    目录内容:"; \
            ls -la /opt/oracle | head -20 | sed 's/^/      /'; \
        fi; \
    fi; \
    \
    # 安装 ODPS 客户端
    if [ "${INSTALL_ODPS}" = "true" ] && [ -f /tmp/db_clients/odpscmd.tar.gz ]; then \
        echo "Installing ODPS client..." && \
        tar -xzf /tmp/db_clients/odpscmd.tar.gz -C /opt/odpscmd && \
        if [ -f /opt/odpscmd/bin/odpscmd ]; then \
            echo "  - ODPS client: ✅ Installed (odpscmd)"; \
            # 创建符号链接方便使用
            ln -sf /opt/odpscmd/bin/odpscmd /usr/local/bin/odpscmd; \
        else \
            echo "  - ODPS client: ⚠️ Not installed"; \
            ls -la /opt/odpscmd | head -10 | sed 's/^/      /'; \
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
            echo "  - Hive: ⚠️ Not installed (HIVE_HOME directory exists but missing executables)"; \
        fi; \
        if [ -d /opt/hadoopclient/HBase ] && [ -f /opt/hadoopclient/HBase/hbase/bin/hbase ]; then \
            echo "  - HBase: ✅ Installed"; \
            components=$((components + 1)); \
        elif [ -d /opt/hadoopclient/HBase ]; then \
            echo "  - HBase: ⚠️ Not installed"; \
        fi; \
        if [ -d /opt/hadoopclient/Spark ] && [ -f /opt/hadoopclient/Spark/spark/bin/spark-shell ]; then \
            echo "  - Spark: ✅ Installed"; \
            components=$((components + 1)); \
        elif [ -d /opt/hadoopclient/Spark ]; then \
            echo "  - Spark: ⚠️ Not installed"; \
        fi; \
        if [ $components -eq 0 ]; then \
            echo "  - Hadoop client: ⚠️ No components detected"; \
        fi; \
    fi; \
    \
    # 显示安装摘要
    echo "════════════════════════════════════════════"; \
    echo "Database clients installation summary:"; \
    echo "  GaussDB: ${INSTALL_GAUSSDB}"; \
    echo "  Vertica: ${INSTALL_VERTICA}"; \
    echo "  Oracle: ${INSTALL_ORACLE}"; \
    echo "  Hadoop: ${INSTALL_HADOOP}"; \
    echo "  ODPS: ${INSTALL_ODPS}"; \
    echo "════════════════════════════════════════════"; \
    \
    # 清理临时文件
    rm -rf /tmp/db_clients

# ==================================================
# 4. 设置环境变量
# ==================================================
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
# 5. matplotlib 全局中文配置
# ==================================================
RUN mkdir -p /usr/local/etc && \
    cat << 'EOF' > /usr/local/etc/matplotlibrc
font.family         : sans-serif
font.sans-serif     : Noto Sans CJK SC, Source Han Sans SC, WenQuanYi Zen Hei, DejaVu Sans
axes.unicode_minus  : False
EOF

# ==================================================
# 6. 启动时初始化数据库配置（条件初始化）
# ==================================================
RUN mkdir -p /usr/local/bin/start-notebook.d
RUN cat << 'EOF' > /usr/local/bin/start-notebook.d/10-db-client-init.sh
#!/usr/bin/env bash
set -e

# 确保生成文件权限为 600
umask 077
HOME_DIR="${HOME}"

# ------------------------------
# 1. 创建必要的配置目录
# ------------------------------
mkdir -p "${HOME_DIR}/.odps"

# ------------------------------
# 2. ~/.pgpass（仅当安装了相关客户端时）
# ------------------------------
PGPASS="${HOME_DIR}/.pgpass"
: > "${PGPASS}"

# GaussDB
if command -v gsql &>/dev/null && [ -n "${GAUSSDB_HOST}" ] && [ -n "${GAUSSDB_PASSWORD}" ]; then
  echo "${GAUSSDB_HOST}:${GAUSSDB_PORT:-5432}:${GAUSSDB_DBNAME:-postgres}:${GAUSSDB_USER:-${USER}}:${GAUSSDB_PASSWORD}" >> "${PGPASS}"
fi

# Vertica
if command -v vsql &>/dev/null && [ -n "${VERTICA_HOST}" ] && [ -n "${VERTICA_PASSWORD}" ]; then
  echo "${VERTICA_HOST}:${VERTICA_PORT:-5433}:${VERTICA_DBNAME:-${VERTICA_USER:-dbadmin}}:${VERTICA_USER:-dbadmin}:${VERTICA_PASSWORD}" >> "${PGPASS}"
fi

# 只在有内容时才设置权限
if [[ -s "${PGPASS}" ]]; then
  chmod 600 "${PGPASS}"
fi

# ------------------------------
# 3. psql / gsql 配置（仅当安装了相关客户端时）
# ------------------------------
if command -v gsql &>/dev/null; then
  cat << 'EORC' > "${HOME_DIR}/.psqlrc"
-- psql / gsql 通用配置
\set PROMPT1 '%n@%M:%> %/%R%# '
\set HISTSIZE 10000
\set VERBOSITY verbose
\timing on
EORC
  cp "${HOME_DIR}/.psqlrc" "${HOME_DIR}/.gsqlrc" 2>/dev/null || true
  chmod 600 "${HOME_DIR}/.psqlrc" "${HOME_DIR}/.gsqlrc" 2>/dev/null || true
fi

# ------------------------------
# 4. vsql 配置（仅当安装了 Vertica 时）
# ------------------------------
if command -v vsql &>/dev/null; then
  cat << 'EORC' > "${HOME_DIR}/.vsqlrc"
-- vsql 交互配置
\set PROMPT1 '%n@%h:%p %d=> '
\timing
EORC
  chmod 600 "${HOME_DIR}/.vsqlrc"
fi

# ------------------------------
# 5. ODPS 配置（仅当安装了 ODPS 时）
# ------------------------------
if command -v odpscmd &>/dev/null && [ -n "${ODPS_ACCESS_ID}" ] && [ -n "${ODPS_ACCESS_KEY}" ]; then
  ODPS_CONFIG="${HOME_DIR}/.odps/odps_config.ini"
  cat << EORC > "${ODPS_CONFIG}"
[default]
access_id = ${ODPS_ACCESS_ID}
access_key = ${ODPS_ACCESS_KEY}
project_name = ${ODPS_PROJECT:-default}
endpoint = ${ODPS_ENDPOINT:-http://service.odps.aliyun.com/api}
EORC
  chmod 600 "${ODPS_CONFIG}"
fi
EOF

RUN chmod +x /usr/local/bin/start-notebook.d/10-db-client-init.sh

# ==================================================
# 7. 全局分页器 less 配置
# ==================================================
RUN mkdir -p /etc/profile.d && \
    cat << 'EOF' > /etc/profile.d/pager.sh
# 使用 less 作为默认分页器
export PAGER=less
export LESS='-RS'
EOF

# ==================================================
# 8. 修复 HOME / 挂载卷权限
# ==================================================
RUN fix-permissions "${HOME}"

# ==================================================
# 9. 健康检查
# ==================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD ["jupyter", "notebook", "list"] || exit 1

# ==================================================
# 10. 显示构建信息
# ==================================================
RUN echo "Build completed: BUILD_TYPE=${BUILD_TYPE}, PIP_INDEX_URL=${PIP_INDEX_URL}"

# ==================================================
# 11. 切回 jovyan 用户
# ==================================================
USER ${NB_UID}
WORKDIR "${HOME}"

CMD ["start-notebook.sh"]