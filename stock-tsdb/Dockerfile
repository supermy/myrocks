# Stock-TSDB Dockerfile
# 基于 Alpine Linux 的轻量级镜像
FROM alpine:3.15

# 维护者信息
LABEL maintainer="Stock-TSDB Team"
LABEL description="Stock Time Series Database - High-performance time series database for stock market data"

# 设置环境变量
ENV LUAROCKS_VERSION=3.8.0
ENV ROCKSDB_VERSION=6.20.3

# 安装系统依赖
RUN apk add --no-cache \
    build-base \
    linux-headers \
    git \
    curl \
    wget \
    bash \
    libstdc++ \
    snappy-dev \
    zlib-dev \
    bzip2-dev \
    lz4-dev \
    zstd-dev \
    gflags-dev \
    gcc \
    g++ \
    make \
    cmake \
    perl \
    python3 \
    py3-pip \
    zeromq-dev \
    && rm -rf /var/cache/apk/*

# 安装 LuaJIT 和 LuaRocks
RUN apk add --no-cache luajit luajit-dev luarocks

# 创建工作目录
WORKDIR /app

# 复制项目文件
COPY . .

# 构建 RocksDB
RUN cd /tmp && \
    wget https://github.com/facebook/rocksdb/archive/v${ROCKSDB_VERSION}.tar.gz && \
    tar xzf v${ROCKSDB_VERSION}.tar.gz && \
    cd rocksdb-${ROCKSDB_VERSION} && \
    make static_lib -j$(nproc) && \
    make install-static && \
    cd /tmp && \
    rm -rf rocksdb-${ROCKSDB_VERSION} v${ROCKSDB_VERSION}.tar.gz

# 安装 Lua 依赖
RUN luarocks install lua-cjson && \
    luarocks install luasocket && \
    luarocks install lua-llthreads2 && \
    luarocks install lzmq

# 构建项目
RUN make

# 创建必要的目录
RUN mkdir -p /data /logs /config

# 暴露端口
# 6379: Redis兼容API端口
# 5555: ZeroMQ集群端口
# 8080: 监控端口
EXPOSE 6379 5555 8080

# 设置卷挂载点
VOLUME ["/data", "/logs", "/config"]

# 设置默认配置文件
RUN cp conf/stock-tsdb.conf /config/stock-tsdb.conf

# 设置启动命令
ENTRYPOINT ["./stock-tsdb-server"]
CMD ["-c", "/config/stock-tsdb.conf"]