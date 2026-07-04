# SVG 设计系统指南 (SVG Design System Guide)

一套统一的、现代化的 SVG 架构图与可视化设计系统。所有使用 SVG 输出的 skill（project-architecture、infographic-poster、diagram-rendering 等）都遵循本指南，确保跨项目、跨 skill 的视觉一致性。

## 核心理念

> 设计系统 = 配色 + 排版 + 组件库 + 动效 = 快速 + 一致 + 专业

不重复造轮子；copypaste 即用；所有代码片段都在这里，开箱即得。

---

## 色彩系统 Color Palette

### 层级色 (Layer Colors)

每个逻辑层有独立的色族，包含：深色（标题/强调）、浅色（背景）、中性色（边框/分割）。

| 层级 | 名称 | 深渐变起 | 深渐变止 | 浅背景 | 卡片边框 | 表情 |
|------|------|---------|---------|--------|---------|------|
| Frontend | 前端 | `#667eea` | `#5a67d8` | `#eef1ff` | `#c3dafe` | 🎨 |
| Backend | 后端 | `#48bb78` | `#38a169` | `#f0fff4` | `#c6f6d5` | ⚙️ |
| Middleware | 中间件 | `#ed8936` | `#dd6b20` | `#fffaf0` | `#fed7aa` | 📦 |
| Database | 数据库 | `#9f7aea` | `#805ad5` | `#faf5ff` | `#e9d8fd` | 💾 |
| External / API | 外部 | `#f6ad55` | `#ed8936` | `#fefcbf` | `#fefcbf` | 🔌 |
| Infra & Ops | 基础设施 | `#a0aec0` | `#718096` | `#f7fafc` | `#cbd5e1` | 🛠️ |

### 通用中性色 (Neutral)

- **背景**: `#f7fafc` — 页面底色
- **标题强**: `#1a202c` — 最深文本
- **标题中**: `#2d3748` — 二级标题
- **正文**: `#4a5568` — 常规文本
- **辅文**: `#718096` — 次要文本
- **弱文 / 标注**: `#a0aec0` — 最淡描述

### 特殊色 (Semantic)

- **成功**: `#48bb78` (Backend green)
- **警告**: `#ed8936` (Middleware orange)
- **错误**: `#f56565`
- **信息**: `#4299e1`
- **箭头 / 连接线**: `#a0aec0` (neutral-muted)

---

## 动态定义 (Defs)

复制整个 `<defs>` 块到 SVG 的 `<head>` 部分。

```xml
<defs>
  <!-- ========== GRADIENTS ========== -->
  <linearGradient id="frontendGrad" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#667eea"/>
    <stop offset="100%" stop-color="#5a67d8"/>
  </linearGradient>
  <linearGradient id="backendGrad" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#48bb78"/>
    <stop offset="100%" stop-color="#38a169"/>
  </linearGradient>
  <linearGradient id="middlewareGrad" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#ed8936"/>
    <stop offset="100%" stop-color="#dd6b20"/>
  </linearGradient>
  <linearGradient id="dbGrad" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#9f7aea"/>
    <stop offset="100%" stop-color="#805ad5"/>
  </linearGradient>
  <linearGradient id="infraGrad" x1="0" y1="1" x2="1" y2="0">
    <stop offset="0%" stop-color="#a0aec0"/>
    <stop offset="100%" stop-color="#718096"/>
  </linearGradient>
  <linearGradient id="externalGrad" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0%" stop-color="#f6ad55"/>
    <stop offset="100%" stop-color="#ed8936"/>
  </linearGradient>

  <!-- ========== SHADOWS ========== -->
  <filter id="shadow" x="-2%" y="-2%" width="104%" height="108%">
    <feDropShadow dx="0" dy="2" stdDeviation="3" flood-color="#00000022"/>
  </filter>
  <filter id="shadowLight" x="-2%" y="-2%" width="104%" height="106%">
    <feDropShadow dx="0" dy="1" stdDeviation="2" flood-color="#00000018"/>
  </filter>

  <!-- ========== MARKERS / ARROWS ========== -->
  <marker id="arrowDown" markerWidth="8" markerHeight="6" refX="4" refY="3" orient="auto">
    <path d="M0,0 L8,3 L0,6 Z" fill="#a0aec0"/>
  </marker>
  <marker id="arrowRight" markerWidth="6" markerHeight="8" refX="3" refY="4" orient="auto">
    <path d="M0,0 L6,4 L0,8 Z" fill="#a0aec0"/>
  </marker>
  <marker id="arrowDashed" markerWidth="8" markerHeight="6" refX="4" refY="3" orient="auto">
    <path d="M0,0 L8,3 L0,6 Z" fill="#0891b2"/>
  </marker>

  <!-- ========== PATTERNS ========== -->
  <pattern id="dots" x="0" y="0" width="4" height="4" patternUnits="userSpaceOnUse">
    <circle cx="2" cy="2" r="1" fill="#cbd5e1"/>
  </pattern>
</defs>
```

### 快速参考：何时用哪个 Filter/Marker

- **shadow** — 重要框、容器、大标题背景
- **shadowLight** — 卡片、子组件、交互元素
- **arrowDown** — 垂直向下的数据流 / 调用链
- **arrowRight** — 水平向右的依赖 / 通信
- **arrowDashed** — 虚线，表示"可选、外部、异步"

---

## 组件库 Component Library

### 1. 层级容器 (Layer Container)

一个完整的层，包含背景色、渐变标题栏、标题文本、阴影。

```xml
<!-- ==================== FRONTEND LAYER ==================== -->
<rect x="30" y="72" width="1040" height="130" 
      fill="#eef1ff" stroke="#667eea" stroke-width="1.5" rx="6" 
      filter="url(#shadowLight)"/>

<!-- Gradient header bar -->
<rect x="30" y="72" width="1040" height="28" 
      fill="url(#frontendGrad)" rx="6"/>

<!-- Accent line under header -->
<rect x="30" y="92" width="1040" height="8" 
      fill="url(#frontendGrad)"/>

<!-- Layer title -->
<text x="550" y="91" text-anchor="middle" 
      font-size="13" font-weight="bold" fill="#fff">
  🎨 前端层 Frontend
</text>
```

**调整参数:**
- `x, y` — 位置
- `width, height` — 尺寸
- `fill="#eef1ff"` — 对应层的浅背景色
- `stroke="#667eea"` — 对应层的深色
- 标题中的表情和文本

---

### 2. 卡片 (Component Card)

一张单一模块 / 服务的卡片，包含标题、描述、标注。

```xml
<rect x="55" y="110" width="300" height="78" 
      fill="#fff" stroke="#c3dafe" stroke-width="1" rx="4" 
      filter="url(#shadowLight)"/>

<!-- Title -->
<text x="205" y="133" text-anchor="middle" 
      font-size="12" font-weight="bold" fill="#434190">
  Admin Frontend (agentscope)
</text>

<!-- Main description (line 1) -->
<text x="205" y="151" text-anchor="middle" 
      font-size="10" fill="#4a5568">
  一站式 Agent 可视化管理平台
</text>

<!-- Main description (line 2) -->
<text x="205" y="168" text-anchor="middle" 
      font-size="10" fill="#4a5568">
  可视化开发 · 调试 · 评估 · MCP 管理
</text>

<!-- Footnote / tech stack -->
<text x="205" y="183" text-anchor="middle" 
      font-size="9" fill="#a0aec0">
  React · TypeScript
</text>
```

**卡片尺寸约定：**
- **宽** — 常见 300px / 310px (按 1100px 宽度，约 3 列排)
- **高** — 78px (3 行文本) / 85px (4 行) / 106px (5 行)
- **间距** — x 间隔 25px，y 间隔 8-10px

**文本样式约定：**
- **标题** — 12px bold, layer-color (e.g. `#434190` for backend)
- **描述** — 10px, `#4a5568` (normal text)
- **标注** — 9px, `#a0aec0` (muted)

---

### 3. 箭头 / 连接线 (Arrows)

```xml
<!-- 垂直向下，实线 -->
<line x1="550" y1="202" x2="550" y2="225" 
      stroke="#a0aec0" stroke-width="1.5" 
      marker-end="url(#arrowDown)"/>

<!-- 水平向右，虚线（外部系统）-->
<line x1="1220" y1="382" x2="1290" y2="382" 
      stroke="#0891b2" stroke-width="1.5" stroke-dasharray="4 3"
      marker-end="url(#arrowDashed)"/>

<!-- 贝塞尔曲线（复杂路由）-->
<path d="M1290 340 C 1100 360, 1090 760, 1100 800" 
      fill="none" stroke="#0891b2" stroke-width="1.5" 
      stroke-dasharray="5 4" 
      marker-end="url(#arrowDashed)"/>
```

**箭头类型：**
- **实线** — 主要调用 / 同步流 (`arrowDown` / `arrowRight`)
- **虚线** — 外部 / 异步 / 可选 (`arrowDashed`, 蓝色 `#0891b2`)
- **虚线间距** — `"4 3"` (短虚线) / `"5 4"` (稍长)

**协议标签** (箭头旁的小字)：
```xml
<text x="560" y="220" font-size="10" fill="#718096" font-weight="600">
  HTTP / SSE
</text>
```

---

### 4. 信息框 / 侧边栏 (Sidebar / Infobox)

用于放置横切设施、外部依赖、部署说明等。

```xml
<!-- Right-side infra box -->
<rect x="1270" y="410" width="330" height="310" 
      fill="#f1f5f9" stroke="#64748b" stroke-width="1.6" 
      stroke-dasharray="6 4" rx="11" 
      filter="url(#shadowLight)"/>

<!-- Title -->
<text x="1290" y="436" font-size="13" font-weight="bold" fill="#334155">
  周边基础设施 INFRA &amp; OPS
</text>

<!-- Subtitle -->
<text x="1290" y="454" font-size="10" fill="#a0aec0" font-style="italic">
  横切所有分层 · 不展开
</text>

<!-- Sub-box within -->
<rect x="1290" y="466" width="290" height="70" 
      fill="#fff" stroke="#cbd5e1" stroke-width="1" rx="8" 
      filter="url(#shadowLight)"/>
```

---

## 排版系统 Typography

使用一致的字体栈和字号。

```css
font-family: "Segoe UI, -apple-system, BlinkMacSystemFont, sans-serif"
```

### 字号与粗细

| 用途 | 大小 | 粗细 | 颜色 | 例子 |
|------|------|------|------|------|
| 页面标题 | 22px | bold (800) | `#1a202c` | "Spring AI Alibaba — 架构全景图" |
| 页面副标题 | 12px | normal | `#718096` | "Architecture Overview" |
| **层标题** | **13px** | **bold** | **#fff** | **"🎨 前端层 Frontend"** |
| 卡片标题 | 12px | bold (700) | layer-color | "Admin Frontend" |
| 卡片描述 | 10px | normal | `#4a5568` | "一站式管理平台" |
| 卡片标注 | 9px | normal | `#a0aec0` | "React · TypeScript" |
| 箭头标签 | 10px | 600 | `#718096` | "HTTP / SSE" |
| 脚注 | 10px | normal | `#a0aec0` | 版权或说明 |

---

## 布局规范 Layout Grid

针对常见的架构图布局。

### 1100px 宽 (标准架构图)

```
margin: 30px
usable width: 1040px

3-column grid per layer:
  each card: ~330px (includes gap)
  gap: 25px
  → 330 + 25 + 330 + 25 + 330 = 1040px ✓
```

### 层高约定

- **Frontend 前端** — 130px
- **Backend 后端** — 230px (可扩展至 280px if needed)
- **Middleware 中间件** — 180px (5 services fit nicely)
- **Database 数据库** — 160px
- **Infra / External (侧框)** — 300–400px

垂直间隔：`y[下层] - y[上层] >= 3px` (箭头空间)

---

## 快速参考 Cheat Sheet

### 复制这个模板快速开始

```xml
<svg xmlns="http://www.w3.org/2000/svg" 
     width="1100" height="820" viewBox="0 0 1100 820" 
     font-family="Segoe UI, -apple-system, sans-serif">
  
  <!-- ===== DEFS ===== 复制上面的整个 defs block ===== -->
  <defs>
    <!-- gradients, shadows, markers -->
  </defs>

  <!-- Background -->
  <rect width="1100" height="820" fill="#f7fafc" rx="8"/>

  <!-- Title -->
  <text x="550" y="36" text-anchor="middle" 
        font-size="22" font-weight="bold" fill="#1a202c">
    YOUR PROJECT — 架构全景图
  </text>

  <!-- === LAYER 1: FRONTEND === -->
  <rect x="30" y="72" width="1040" height="130" 
        fill="#eef1ff" stroke="#667eea" stroke-width="1.5" rx="6" 
        filter="url(#shadowLight)"/>
  <!-- ... populate with cards ... -->

  <!-- Arrow Frontend → Backend -->
  <line x1="550" y1="202" x2="550" y2="225" 
        stroke="#a0aec0" stroke-width="1.5" 
        marker-end="url(#arrowDown)"/>

  <!-- === LAYER 2: BACKEND === -->
  <!-- ... -->

</svg>
```

### 一句调用的色盘

需要某层的颜色？查这个表直接贴：

- Frontend 层 → `#667eea` (深) / `#eef1ff` (浅) / `#c3dafe` (边) / `url(#frontendGrad)` (渐变)
- Backend 层 → `#48bb78` / `#f0fff4` / `#c6f6d5` / `url(#backendGrad)`
- Middleware 层 → `#ed8936` / `#fffaf0` / `#fed7aa` / `url(#middlewareGrad)`
- Database 层 → `#9f7aea` / `#faf5ff` / `#e9d8fd` / `url(#dbGrad)`
- Infra 层 → `#a0aec0` / `#f7fafc` / `#cbd5e1` / `url(#infraGrad)`

---

## 应用示例 Examples

### 例 1: 架构图 (Architecture Diagram)

使用本指南的完整示例见：`/d/project/spring-ai-alibaba/docs/architecture.svg`

- 5 层完整架构
- 30+ 卡片
- 侧边栏 (Infra & Ops)
- 垂直数据流 + 虚线外部系统

### 例 2: 信息海报 (Infographic Poster)

使用本指南色系的信息海报（待建，reserved for future skill）

---

## 扩展与定制 Customization

### 添加新的层颜色

1. 在色彩系统表中加一行
2. 在 `<defs>` 中加对应的 `<linearGradient id="xxxGrad">`
3. 在布局中引用 `fill="url(#xxxGrad)"` 和 `stroke="#xyz"`

### 更改阴影强度

编辑 filter 中的 `stdDeviation` 和 `flood-color` opacity：
- 更深阴影：`stdDeviation="4"` + `#00000033`
- 更轻阴影：`stdDeviation="1"` + `#00000010`

### 响应式 / 不同宽度

当 SVG 宽度不同时，按比例调整：
- 1100px → 标准宽（本文档）
- 1400px → 扩大内容，减少层高挤压
- 800px → 单列布局，卡片堆叠（mobile friendly）

---

## 许可与归属 License

此设计系统基于 Tailwind CSS 色彩理论和现代 SaaS 设计趋势。
可自由复用于内部项目、公开文档、演示文稿。

---

**Last Updated**: 2025-06-27  
**Created By**: Claude Code · SVG Design System  
**Target Audience**: All skills outputting SVG diagrams + visualizations
