/*
 * Copyright 2024-2026 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.alibaba.cloud.ai.studio.admin.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;
import java.util.Map;

/**
 * Response DTO for {@code GET /console/v1/overview}.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class OverviewResponse {

    private OverviewStats stats;
    private Map<String, Integer> experimentStatus;
    private List<TopPromptVersion> topPromptVersions;
    private List<RecentActivity> recentActivities;
    private List<DocIndexStatus> docIndexStatus;

    // ── Inner types ──

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class OverviewStats {
        private StatItem prompts;
        private StatItem versions;
        private StatItem experiments;
        private StatItem datasets;
        private StatItem knowledgeBases;
        private StatItem models;
    }

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class StatItem {
        private long total;
    }

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class TopPromptVersion {
        private String promptKey;
        private int preCount;
        private int releaseCount;
    }

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class RecentActivity {
        /** One of: prompt_version, experiment, dataset */
        private String type;
        private String title;
        /** epoch millis */
        private long time;
        private String description;
    }

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class DocIndexStatus {
        private String kbId;
        private String kbName;
        private int totalDocs;
        private int indexedDocs;
        private double progress;
    }

}
