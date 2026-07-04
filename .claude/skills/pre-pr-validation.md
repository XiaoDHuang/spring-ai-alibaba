# PR 预验证 (Pre-PR Validation)

一键运行 PR 提交前的全套本地质量检查流水线，提前发现问题避免 CI 失败回退。

## 描述

每个开发者提交 PR 前都需要运行一系列检查：编译验证、代码格式化、代码风格检查、许可证头检查等。本 skill 将这些步骤串成一键操作，减少记忆负担，避免因漏检查导致 CI 失败。

遵循项目 [CONTRIBUTING.md](../../CONTRIBUTING.md) 中定义的检查流程。

## 参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `module` | string | 否 | 要检查的模块名称，例如 `:spring-ai-alibaba-admin` 或 `examples/chatbot`。不填则检查整个项目 |
| `skipTests` | boolean | 否 | 是否跳过测试，默认 `true` |
| `fixFormat` | boolean | 否 | 是否自动修复格式问题，默认 `true` |

## 执行步骤

1. **参数解析**：解析输入参数，设置 Maven 命令参数
2. **清理编译**：执行 `mvn clean compile`，验证代码编译通过
3. **代码格式化**（如果 `fixFormat=true`）：
   - 执行 `./mvnw spring-javaformat:apply` 应用 Spring Java 格式规范
   - 执行 `./mvnw spotless:apply` 清理未使用的导入
4. **代码风格检查**：执行 `./mvnw checkstyle:check`，检查代码风格是否合规
5. **许可证检查**：执行 `make licenses-check`，验证所有文件都有正确的 Apache 2.0 许可证头
6. **格式校验**：执行 `make format-check`，验证代码格式符合规范
7. **结果汇总**：输出所有检查结果，标记失败项，给出修复建议

## 允许工具

```yaml
- tool: Bash
  prompt: run maven and make commands for validation checks
```

## 输出示例

```
🚀 Starting Pre-PR Validation
=============================

✓ Compile: clean compile completed successfully
✓ Format: spring-javaformat applied
✓ Format: spotless import cleanup completed
✓ Checkstyle: 0 errors found
✓ License check: all files have valid license headers
✓ Format check: all files are properly formatted

=============================
✅ All checks passed! Ready to commit and create PR.
```

## 优先级

HIGH - 每个 PR 必做，减少 CI 失败率，节省开发者时间

**Created by**: Claude Code · Spring AI Alibaba Workflow
**Last Updated**: 2025-06-28
