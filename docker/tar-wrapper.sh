#!/usr/bin/env bash
# tar 包装器: 某些源码包归档内文件属主为普通 uid(如 1000), 容器 root 解包
# 默认会 chown 恢复属主; 在 colima 共享挂载上 chown 被拒绝导致解包失败。
# GNU tar 支持 TAR_OPTIONS, 这里强制 --no-same-owner (文件归属解包用户,
# 不影响内容/权限位)。构建输出目录走 Docker 命名卷时本无此问题, 此包装器
# 用于覆盖所有挂载场景。
export TAR_OPTIONS="--no-same-owner ${TAR_OPTIONS:-}"
exec /usr/bin/tar "$@"
