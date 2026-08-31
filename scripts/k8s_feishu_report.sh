#!/bin/bash
set -eu

# ==============================================================================
# 脚本名称: k8s_feishu_report.sh (生产加固版)
# 功能描述: 多维动态加权健康评分、智能过滤 Completed Job、异常 Pod 精准提取与飞书卡片播报
# ==============================================================================

# 1. 飞书自定义机器人 Webhook (请替换为您自己的 Webhook)
FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/05ce99c0-054b-40bd-9f93-93058ea3cfc3"

# 2. 基础环境与时间戳
HOSTNAME_STR=$(hostname)
NODE_IP=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "127.0.0.1")
REPORT_TIME=$(date "+%Y-%m-%d %H:%M:%S")

# 3. 采集系统硬件基础指标
CPU_CORES=$(nproc)
LOAD_1MIN=$(awk '{print $1}' /proc/loadavg)
MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
MEM_USED=$(free -m | awk '/Mem:/ {print $3}')
MEM_RATE=$(awk -v u="${MEM_USED}" -v t="${MEM_TOTAL}" 'BEGIN {printf "%.1f", (u/t)*100}')
DISK_USED_RATE=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')

# 4. 精准分析 Kubernetes Pod 状态机
# 提取所有处于非 Running 且非 Completed 状态的真实异常 Pod
ABNORMAL_PODS_RAW=$(kubectl get pods -A --no-headers | awk '$4 !~ /Running|Completed/ {print $1"/"$2" ("$4")"}' || true)
ABNORMAL_COUNT=$(echo "${ABNORMAL_PODS_RAW}" | grep -v '^$' | wc -l || true)
TOTAL_PODS=$(kubectl get pods -A --no-headers | wc -l)
HEALTHY_PODS=$((TOTAL_PODS - ABNORMAL_COUNT))

# 5. 多维度动态加权健康评分计算 (满分 100 分)
SCORE=100
DEDUCTION_REASONS=""

# 规则 A: 异常 Pod 扣分 (每个扣 15 分)
if [ "${ABNORMAL_COUNT}" -gt 0 ]; then
    POD_DEDUCT=$((ABNORMAL_COUNT * 15))
    SCORE=$((SCORE - POD_DEDUCT))
    DEDUCTION_REASONS="${DEDUCTION_REASONS}\n• 存在 ${ABNORMAL_COUNT} 个异常 Pod (-${POD_DEDUCT}分)"
fi

# 规则 B: 内存水位扣分 (>=80% 扣 10 分, >=90% 扣 20 分)
MEM_INT=${MEM_RATE%.*}
if [ "${MEM_INT}" -ge 90 ]; then
    SCORE=$((SCORE - 20))
    DEDUCTION_REASONS="${DEDUCTION_REASONS}\n• 内存使用率超过 90% 严重告警 (-20分)"
elif [ "${MEM_INT}" -ge 80 ]; then
    SCORE=$((SCORE - 10))
    DEDUCTION_REASONS="${DEDUCTION_REASONS}\n• 内存使用率超过 80% 预警 (-10分)"
fi

# 规则 C: 磁盘水位扣分 (>=85% 扣 15 分)
if [ "${DISK_USED_RATE}" -ge 85 ]; then
    SCORE=$((SCORE - 15))
    DEDUCTION_REASONS="${DEDUCTION_REASONS}\n• 根分区磁盘使用率超过 85% (-15分)"
fi

# 保证分数最低为 0 分
if [ "${SCORE}" -lt 0 ]; then
    SCORE=0
fi

# 6. 根据最终综合得分匹配卡片主题色与标题
if [ "${SCORE}" -ge 90 ]; then
    HEADER_TEMPLATE="green"
    HEALTH_TITLE="【边缘集群巡检】K3s 系统运行健康 (${SCORE}分)"
    POD_DETAIL_TEXT="✅ 所有微服务与系统 Pod 均处于健康活跃状态。"
elif [ "${SCORE}" -ge 75 ]; then
    HEADER_TEMPLATE="orange"
    HEALTH_TITLE="【边缘集群预警】K3s 存在资源压力或轻微告警 (${SCORE}分)"
    POD_DETAIL_TEXT="⚠️ **扣分与预警项**:${DEDUCTION_REASONS}"
else
    HEADER_TEMPLATE="red"
    HEALTH_TITLE="【边缘集群故障】K3s 触发生产级告警，请立即处置！(${SCORE}分)"
    POD_DETAIL_TEXT="🚨 **异常 Pod 清单**:\n\`\`\`\n${ABNORMAL_PODS_RAW}\n\`\`\`"
fi

# 7. 组装飞书交互式卡片 JSON
JSON_PAYLOAD=$(cat <<EOF
{
  "msg_type": "interactive",
  "card": {
    "config": {
      "wide_screen_mode": true
    },
    "header": {
      "template": "${HEADER_TEMPLATE}",
      "title": {
        "content": "${HEALTH_TITLE}",
        "tag": "plain_text"
      }
    },
    "elements": [
      {
        "tag": "div",
        "fields": [
          {
            "is_short": true,
            "text": {
              "tag": "lark_md",
              "content": "**🖥️ 节点信息**\n${HOSTNAME_STR} (${NODE_IP})"
            }
          },
          {
            "is_short": true,
            "text": {
              "tag": "lark_md",
              "content": "**⏱️ 巡检时间**\n${REPORT_TIME}"
            }
          }
        ]
      },
      {
        "tag": "hr"
      },
      {
        "tag": "div",
        "fields": [
          {
            "is_short": true,
            "text": {
              "tag": "lark_md",
              "content": "**⚙️ CPU 负载 (1m / 核心)**\n${LOAD_1MIN} / ${CPU_CORES} Core"
            }
          },
          {
            "is_short": true,
            "text": {
              "tag": "lark_md",
              "content": "**🧠 内存使用率**\n${MEM_RATE}% (${MEM_USED}MB / ${MEM_TOTAL}MB)"
            }
          },
          {
            "is_short": true,
            "text": {
              "tag": "lark_md",
              "content": "**💾 根磁盘使用率**\n${DISK_USED_RATE}%"
            }
          },
          {
            "is_short": true,
            "text": {
              "tag": "lark_md",
              "content": "**☸️ K3s Pod 正常率**\n${HEALTHY_PODS} / ${TOTAL_PODS} (健康/总数)"
            }
          }
        ]
      },
      {
        "tag": "div",
        "text": {
          "tag": "lark_md",
          "content": "${POD_DETAIL_TEXT}"
        }
      },
      {
        "tag": "hr"
      },
      {
        "tag": "div",
        "text": {
          "tag": "lark_md",
          "content": "**🛡️ 核心微服务网关入口状态**:\n• 🌐 Web 门户: [https://app.edge.internal](https://app.edge.internal)\n• 📝 Memos 笔记: [https://memos.edge.internal](https://memos.edge.internal)\n• 📊 Grafana 大盘: [https://grafana.edge.internal](https://grafana.edge.internal)\n• 📈 Prometheus: [https://prometheus.edge.internal](https://prometheus.edge.internal)"
        }
      },
      {
        "tag": "action",
        "actions": [
          {
            "tag": "button",
            "text": {
              "tag": "plain_text",
              "content": "🚀 直达 Grafana 监控大盘"
            },
            "type": "primary",
            "url": "https://grafana.edge.internal"
          }
        ]
      }
    ]
  }
}
EOF
)

# 8. 发送至飞书群机器人
curl -s -X POST -H "Content-Type: application/json" -d "${JSON_PAYLOAD}" "${FEISHU_WEBHOOK}" > /dev/null
echo "[+] 飞书巡检卡片已成功推送至群聊！"
