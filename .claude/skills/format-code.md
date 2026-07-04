# 格式化代码 (Format Code)

自动格式化代码，应用 Spring Java 格式规范并清理未使用导入。

## 描述

CI 每次 PR 都会运行格式检查，新代码经常因为格式不对被打回。本 skill 一键执行 `spring-javaformat:apply` + `spotless:apply`，自动格式化代码并清理未使用导入，保证一次通过格式检查。

## 参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `scope` | string | 否 | 格式化范围：`all`（全项目）、`module`（当前模块）、指定模块名，默认 `module` |
| `validateOnly` | boolean | 否 | 仅校验不修改，默认 `false`（修复模式） |

## 执行步骤

1. **参数解析**：解析格式化范围，确定 Maven 命令参数
2. **Spring 格式化**：
   - 如果 `validateOnly=true`：执行 `./mvnw <scope-args> spring-javaformat:validate`
   - 如果 `validateOnly=false`：执行 `./mvnw <scope-args> spring-javaformat:apply`
3. **清理导入**：
   - 如果 `validateOnly=false`：执行 `./mvnw <scope-args> spotless:apply` 移除未使用导入
4. **结果统计**：输出格式化结果，告知修改了多少文件

## 允许工具

```yaml
- tool: Bash
  prompt: run maven formatting commands
```

## 输出示例

```
🎨 Formatting code...
=====================

✓ spring-javaformat: applied to 12 files
✓ spotless:apply: removed unused imports from 8 files

=====================
✅ Format completed! 12 files modified.
```

## 优先级

MEDIUM-HIGH - 每次提交都需要，减少格式相关 CI 失败率

**Created by**: Claude Code · Spring AI Alibaba Workflow
**Last Updated**: 2025-06-28
