# 构建镜像：Ruby 3.3（Redmine 6.1 官方支持的运行时）+ 插件测试所需依赖。
#
# 依赖在镜像层预装，避免每次流水线都 apt install / gem install，
# 既提速也让流水线脚本保持纯粹（只跑测试命令）。
FROM ruby:3.3-bookworm

ENV BUNDLE_PATH=/root/.cache/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    LANG=C.UTF-8

# 编译原生 gem（sqlite3 / nokogiri 等）所需的最小工具链。
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential \
       git \
       libsqlite3-dev \
       libyaml-dev \
       pkg-config \
       zlib1g-dev \
       openssh-client \
       rsync \
       curl \
    && rm -rf /var/lib/apt/lists/*

# 测试运行所需的 gem 固定在镜像内，与插件运行时依赖解耦。
RUN gem install --no-document \
      minitest \
      activesupport \
      simplecov \
      webmock

WORKDIR /workspace
