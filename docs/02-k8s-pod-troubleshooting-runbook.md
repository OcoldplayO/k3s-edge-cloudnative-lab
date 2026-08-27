# 📕 生产级 K8s 状态机异常排查与自愈演练 Runbook

## 一、 启动探针与存活探针协同 (解决数据库冷启动死锁)
* **故障现象：** MySQL 5.7 初次初始化建库耗时较长，存活探针过早介入误判超时，导致容器陷入无限 `Killing` 重启死循环。
* **解决方案：** 引入 `startupProbe` 赋予 120 秒初始化缓冲期，配合 `livenessProbe` 实现健康监控。

## 二、 OOMKilled (Exit Code 137) 与 CrashLoopBackOff 故障取证
* **判定铁证：** `kubectl describe pod` 捕获 `Reason: OOMKilled`、`Exit Code: 137`（128 + 9，SIGKILL 强杀）。
* **自愈机制：** 配合 cgroup 内存限额与指数退避重试保护宿主机稳定。
