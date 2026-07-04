# Spring AI Alibaba Project Guide (for AI coding assistants)

> This guide keeps it concise — full detailed documentation lives in the `docs/` directory.

## Project Overview

Spring AI Alibaba is a production-ready framework for building **Agentic, Workflow, and Multi-agent** applications. It is an implementation of the Spring AI framework tailored for Alibaba Cloud services (DashScope, Nacos, etc.) and provides a complete ecosystem with built-in context engineering and human-in-the-loop support.

## Key Features

- Multi-Agent Orchestration with built-in patterns (Sequential, Parallel, Routing, Loop)
- Context Engineering with human-in-the-loop, context compaction, editing, model call limits
- Graph-based workflow with conditional routing, nested graphs, parallel execution
- A2A (Agent-to-Agent) support with Nacos integration
- Rich model support (DashScope, OpenAI, DeepSeek) and MCP (Model Context Protocol)
- One-stop visual agent development platform

## Repository Structure

```
spring-ai-alibaba/
├── spring-ai-alibaba-agent-framework/  # Multi-agent framework (pre-built agent patterns)
├── spring-ai-alibaba-graph-core/          # Graph workflow runtime (persistence, state management, orchestration)
├── spring-ai-alibaba-studio/            # Embedded visual debugging UI (frontend + backend)
├── spring-ai-alibaba-admin/           # One-stop Agent platform (visual dev, observability, MCP management)
├── spring-ai-alibaba-bom/             # Bill of Materials for dependency management
├── spring-boot-starters/             # Spring Boot auto-configuration starters
│   ├── spring-ai-alibaba-starter-a2a-nacos/     # Nacos A2A communication
│   ├── spring-ai-alibaba-starter-builtin-nodes/    # Built-in workflow nodes
│   ├── spring-ai-alibaba-starter-config-nacos/  # Dynamic config with Nacos
│   └── spring-ai-alibaba-starter-graph-observation/ # Observability
├── examples/                          # Example applications
│   ├── chatbot/                       # Basic chatbot example
│   ├── deepresearch/                  # Deep research agent example
│   └── documentation/                 # Documentation examples
├── tools/                             # Build and linting tools
└── docs/                              # Documentation (all detailed docs here)
    ├── setup-guide.md                   # Newcomer environment setup guide → [docs/setup-guide.md](docs/setup-guide.md)
    ├── env-checklist.md                 # Environment dependency checklist (middleware, ports, env vars) → [docs/env-checklist.md](docs/env-checklist.md)
    ├── api-list.md                      # REST API endpoint list, grouped by module → [docs/api-list.md](docs/api-list.md)
    ├── data-model.md                    # Core data model, entity/DTO separation → [docs/data-model.md](docs/data-model.md)
    ├── smoke-test-result.md             # Core API smoke test results → [docs/smoke-test-result.md](docs/smoke-test-result.md)
    ├── data-model-er.svg               # ER diagram SVG → [docs/data-model-er.svg](docs/data-model-er.svg)
    ├── module-deps.svg                # Module dependency graph → [docs/module-deps.svg](docs/module-deps.svg)
    └── external-deps.svg              # External dependency graph → [docs/external-deps.svg](docs/external-deps.svg)
```

## Building

### Prerequisites

- **JDK**: 17 (required by the `java.version` project property)
- **Maven**: 3.6+
- **Git**

### Common Build Commands

```shell
# Build the entire project (skip tests)
./mvnw -B package -DskipTests

# Build a specific module
./mvnw -pl :<module-name> -B package -DskipTests

# Clean the project
./mvnw clean

# Run all tests
./mvnw test
```

## Coding Conventions

- Follow **Spring AI** standard code formatting.
- Use **Apache 2.0** license headers for all Java files.
- **Java 17** language features are encouraged (records, switch expressions, text blocks).
- Avoid `System.out.println` — use SLF4J logging.
- Use `final` for local variables and parameters where appropriate.
- Use Lombok annotations (`@Data`, `@Slf4j`, etc.) to reduce boilerplate.

## Documentation Index

- [REST API 接口清单](docs/api-list.md) — grouped by module, complete endpoint documentation
- [核心数据模型](docs/data-model.md) — entity/DTO separation, full table definitions + relation map
- [核心数据模型 ER 图](docs/data-model-er.svg) — visual entity relation diagram

## AI Coding Tips

1.  **JDK Version**: Project targets JDK 17 — use appropriate language features.
2.  **Spring Boot**: Uses Spring Boot 3.x — be aware of the `jakarta.*` namespace vs `javax.*`.
3.  **Dependencies**: Check `spring-ai-alibaba-bom` or the parent POM for version management.
4.  **Makefile**: Use the root Makefile for linting and license checks.
5.  **Adding Features**: When adding new features, prefer putting them in `spring-ai-alibaba-agent-framework` (for generic agent features) or `spring-boot-starters` (for Spring Boot starters) depending on scope.
6.  **Admin Module Build**: The `spring-ai-alibaba-admin` module uses its own parent POM with `${revision}` placeholder. Always pass `-Drevision=1.0.0-SNAPSHOT` when running Maven in this module. After `mvn install`, verify that installed POMs in `~/.m2` have `${revision}` resolved; if not, run `sed -i 's/${revision}/1.0.0-SNAPSHOT/g'` on them before running tests. The root project's `flatten-maven-plugin` does NOT propagate to the admin sub-reactor.
7.  **Auth Interceptor Coverage**: Endpoints under `/api/**` (non-v1) are NOT automatically protected by any interceptor — only `/api/v1/**` (ApiKey) and `/console/v1/**` (Token) are covered. Every new `/api/**` endpoint must be explicitly registered in `InterceptorConfig.java` adding `.addPathPatterns("/api/<module>/**")` to `TokenAuthInterceptor`.
8.  **Dual ORM**: Admin database uses **JPA** (`@Table`, `@Id`, `@GeneratedValue` — see `PromptVersionDO`). Agentscope database uses **MyBatis-Plus** (`@TableName`, `@TableId`, `BaseMapper`). When adding queries, match the ORM to the target database: if the table is in `admin` schema, use JPA Repository or JPQL; if in `agentscope` schema, use MyBatis-Plus `BaseMapper` + XML mapper. Do NOT mix them — JPA entities do NOT have `@TableName` and MyBatis-Plus entities do NOT have `@Table`.
9.  **Cross-DB Service Placement**: Services that query BOTH `admin` and `agentscope` databases must be placed in `server-start` module (NOT `server-core`). Follow the precedent of `ModelConfigBridgeServiceImpl`: inject the agentscope库 mapper (e.g. `KnowledgeBaseMapper`) directly into a server-start service, and do memory-side aggregation for the admin库 results. Server-core cannot depend on server-start, so cross-DB logic that needs both DataSources must live in server-start.
10. **MyBatis-Plus `selectCount(null)` Returns Null**: When `BaseMapper.selectCount(null)` is called on an empty table, MyBatis-Plus returns `null`, NOT `0`. Always wrap with a null-guard: `Long v = mapper.selectCount(null); return v == null ? 0L : v;`. This applies to all agentscope库 `BaseMapper` invocations in server-start services.

## Prohibited Areas (do NOT edit these unless explicitly asked)

- `.git/`
- `node_modules/`
- `build/`
- `*.iml`
- `*.swp`, `*.swo`, `*~`
- `.idea/`

## Legacy / Historical Notes

> (leave this section empty for project maintainer to fill historical change notes)
