# 边缘云原生集群 (K3s) 架构设计与动态存储 (CSI) 治理

## 一、 架构选型与控制面托管
针对企业边缘机房资源受限场景，采用轻量级 K3s 结合 Linux 原生 `systemd` 守护进程托管，将控制面内存占用压缩至 500MB 以内。

## 二、 动态存储供给 (Local-Path CSI)
摒弃传统裸 HostPath 挂载，声明基于 `local-path` 的 StorageClass 与 PVC，实现 `WaitForFirstConsumer` 延迟绑定与 Pod 漂移数据持久化。
