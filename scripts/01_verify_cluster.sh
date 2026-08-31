#!/bin/bash
# 1. 辅助脚本与演练清单
echo "=== ☸️ K3s 集群控制面与系统组件健康度检查 ==="
kubectl get nodes -o wide
echo "=== 📦 业务命名空间 (edge-apps) 资源清单 ==="
kubectl get pods,svc,pvc,ingress -n edge-apps -o wide
