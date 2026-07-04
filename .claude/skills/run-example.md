# 运行示例项目 (Run Example)

一键构建并启动 Spring AI Alibaba 示例项目，自动处理路径和参数。

## 描述

项目提供了丰富的示例代码展示不同功能。开发者和用户经常需要运行示例体验功能，但每个示例的启动命令格式不统一（有的用 `-pl`，有的用 `-f`）。本 skill 自动识别示例路径，生成正确的 Maven 参数，一键启动示例。

## 参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | 是 | 示例名称，例如 `chatbot`, `deepresearch`, `voice-agent`, `multiagent-patterns/sequential` |
| `apiKey` | string | 否 | LLM API Key（DashScope/OpenAI 等）。如果不提供，尝试从环境变量读取 |
| `skipBuild` | boolean | 否 | 是否跳过预构建直接运行，默认 `false` |
| `args` | string | 否 | 额外的 Spring Boot 启动参数 |

## 执行步骤

1. **参数解析**：解析示例名称，在 `examples/` 目录下查找匹配的示例路径
2. **路径识别**：自动判断使用 `-pl` 还是 `-f` 参数格式
3. **环境变量**：如果提供了 `apiKey`，设置对应环境变量（`AI_DASHSCOPE_API_KEY` 或 `OPENAI_API_KEY` 等根据示例自动判断）
4. **预构建**（如果 `skipBuild=false`）：执行 `./mvnw <module-args> package -DskipTests` 构建项目
5. **启动应用**：执行 `./mvnw <module-args> spring-boot:run` 启动示例应用
6. **输出信息**：打印访问地址和可用的接口

## 允许工具

```yaml
- tool: Bash
  prompt: run maven spring-boot:run command for the example
```

## 支持的示例

- `chatbot` - 基础聊天机器人示例
- `deepresearch` - Deep Research 智能深度研究 Agent
- `voice-agent` - 语音对话 Agent 示例
- `multimodal` - 多模态理解与生成示例
- `multiagent-patterns/*` - 多种多 Agent 编排模式示例
- `dataagent` - 自然语言转 SQL 数据 Agent
- `jmanus` - JManus 实现示例

## 输出示例

```
🚀 Starting example: chatbot
===========================

• Example path: examples/chatbot
• DashScope API Key: found in environment
• Building... build completed successfully
• Starting application...

✅ Example started successfully
📝 Open http://localhost:8080/chatui/index.html in browser to chat
```

## 优先级

HIGH - 高频用户操作，改善开发者体验，统一文档格式

**Created by**: Claude Code · Spring AI Alibaba Workflow
**Last Updated**: 2025-06-28
