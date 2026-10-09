# frozen_string_literal: true

# 校验本地化文件：每个 locale 文件可解析，且键集合彼此一致。
#
# 单独成文件而非内联在 shell 里，是因为 CI 容器的 POSIX locale 会把源码中的
# 中文按 US-ASCII 处理导致语法错误；独立文件可显式声明 UTF-8。
require 'yaml'

# CI 容器的 POSIX locale 会让 IO 默认按 US-ASCII 编码，中文输出会抛
# Encoding::UndefinedConversionError，这里统一强制 UTF-8。
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8
$stdout.set_encoding(Encoding::UTF_8)
$stderr.set_encoding(Encoding::UTF_8)

files = Dir[File.expand_path('../config/locales/*.yml', __dir__)].sort

if files.empty?
  warn '!! 未找到本地化文件'
  exit 1
end

parsed = files.to_h do |file|
  [file, YAML.load_file(file, aliases: true)]
end

keys = parsed.transform_values { |data| data.values.first.keys.sort }
baseline_file, baseline = keys.first

failed = false
keys.each do |file, list|
  next if list == baseline

  failed = true
  warn "本地化键不一致：#{File.basename(file)}（对比 #{File.basename(baseline_file)}）"
  warn "  缺少： #{(baseline - list).inspect}"
  warn "  多余： #{(list - baseline).inspect}"
end

if failed
  exit 1
end

puts "本地化文件一致：#{files.map { |f| File.basename(f) }.join(', ')}"
