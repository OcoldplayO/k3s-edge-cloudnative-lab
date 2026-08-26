#!/bin/bash
echo "[INFO] 正在模拟数据库 Pod 物理崩溃并测试 StatefulSet 自动自愈..."
kubectl delete pod edge-mysql-0 -n edge-apps
echo "[INFO] 正在监视 Pod 重建与存储动态重新挂载过程 (按 Ctrl+C 退出)..."
kubectl get pods -n edge-apps -w
