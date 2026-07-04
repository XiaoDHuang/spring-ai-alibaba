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
package com.alibaba.cloud.ai.studio.admin.service.impl;

import com.alibaba.cloud.ai.studio.admin.dto.OverviewResponse;
import com.alibaba.cloud.ai.studio.admin.mapper.DatasetMapper;
import com.alibaba.cloud.ai.studio.admin.mapper.ExperimentMapper;
import com.alibaba.cloud.ai.studio.admin.mapper.PromptMapper;
import com.alibaba.cloud.ai.studio.admin.mapper.PromptVersionMapper;
import com.alibaba.cloud.ai.studio.admin.repository.ModelConfigRepository;
import com.alibaba.cloud.ai.studio.admin.service.OverviewService;
import com.alibaba.cloud.ai.studio.core.base.entity.DocumentEntity;
import com.alibaba.cloud.ai.studio.core.base.entity.KnowledgeBaseEntity;
import com.alibaba.cloud.ai.studio.core.base.mapper.DocumentMapper;
import com.alibaba.cloud.ai.studio.core.base.mapper.KnowledgeBaseMapper;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.stream.Collectors;

/**
 * Overview service — aggregates platform stats from admin + agentscope databases.
 * <p>
 * Strategy: query each DB separately, aggregate in memory (Plan A).
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class OverviewServiceImpl implements OverviewService {

    // ── admin 库 mappers ──
    private final PromptMapper promptMapper;
    private final PromptVersionMapper promptVersionMapper;
    private final ExperimentMapper experimentMapper;
    private final DatasetMapper datasetMapper;
    private final ModelConfigRepository modelConfigRepository;

    // ── agentscope 库 mappers ──
    private final KnowledgeBaseMapper knowledgeBaseMapper;
    private final DocumentMapper documentMapper;

    @Override
    public OverviewResponse getOverview() {
        return OverviewResponse.builder()
            .stats(buildStats())
            .experimentStatus(buildExperimentStatus())
            .topPromptVersions(buildTopPromptVersions())
            .recentActivities(buildRecentActivities())
            .docIndexStatus(buildDocIndexStatus())
            .build();
    }

    // ──────────────────────── Stats ────────────────────────

    private OverviewResponse.OverviewStats buildStats() {
        long prompts = promptMapper.selectCount(null, null, null);
        long versions = promptVersionMapper.selectCountByPromptKey(null, null);
        long experiments = experimentMapper.count(null, null);
        long datasets = datasetMapper.selectCount(null);
        long kbs = safeCount(knowledgeBaseMapper.selectCount(null));
        long models = modelConfigRepository.count(null, null, null);
        return OverviewResponse.OverviewStats.builder()
            .prompts(new OverviewResponse.StatItem(prompts))
            .versions(new OverviewResponse.StatItem(versions))
            .experiments(new OverviewResponse.StatItem(experiments))
            .datasets(new OverviewResponse.StatItem(datasets))
            .knowledgeBases(new OverviewResponse.StatItem(kbs))
            .models(new OverviewResponse.StatItem(models))
            .build();
    }

    // ─────────────────── Experiment Status ─────────────────

    private Map<String, Integer> buildExperimentStatus() {
        Map<String, Integer> result = new LinkedHashMap<>();
        try {
            List<Map<String, Object>> rows = experimentMapper.selectStatusCounts();
            for (Map<String, Object> row : rows) {
                String status = String.valueOf(row.get("status"));
                Object cnt = row.get("cnt");
                result.put(status, cnt instanceof Number ? ((Number) cnt).intValue() : 0);
            }
        } catch (Exception e) {
            log.warn("Failed to query experiment status counts", e);
        }
        // ensure all known statuses present
        for (String s : Arrays.asList("DRAFT", "RUNNING", "COMPLETED", "FAILED", "STOPPED")) {
            result.putIfAbsent(s, 0);
        }
        return result;
    }

    // ──────────────── Top Prompt Versions ──────────────────

    private List<OverviewResponse.TopPromptVersion> buildTopPromptVersions() {
        try {
            List<Map<String, Object>> rows = promptVersionMapper.selectGroupByPromptKeyAndStatus(20);
            Map<String, OverviewResponse.TopPromptVersion> map = new LinkedHashMap<>();
            for (Map<String, Object> row : rows) {
                String key = String.valueOf(row.get("promptKey"));
                String status = String.valueOf(row.get("status"));
                int cnt = ((Number) row.get("cnt")).intValue();
                OverviewResponse.TopPromptVersion tpv = map.computeIfAbsent(key,
                    k -> OverviewResponse.TopPromptVersion.builder().promptKey(k).preCount(0).releaseCount(0).build());
                if ("release".equals(status)) tpv.setReleaseCount(tpv.getReleaseCount() + cnt);
                else tpv.setPreCount(tpv.getPreCount() + cnt);
            }
            return new ArrayList<>(map.values());
        } catch (Exception e) {
            log.warn("Failed to query top prompt versions", e);
            return List.of();
        }
    }

    // ──────────────── Recent Activities ────────────────────

    private List<OverviewResponse.RecentActivity> buildRecentActivities() {
        // Collect recent items from 3 tables and merge in memory.
        List<OverviewResponse.RecentActivity> activities = new ArrayList<>();
        try {
            // prompt_version
            promptVersionMapper.selectListByPromptKey(null, null, 0, 20)
                .forEach(pv -> activities.add(OverviewResponse.RecentActivity.builder()
                    .type("prompt_version")
                    .title(pv.getPromptKey() + " " + pv.getVersion())
                    .time(toEpoch(pv.getCreateTime()))
                    .description(pv.getStatus())
                    .build()));
            // experiment
            experimentMapper.selectList(null, null, 0, 20)
                .forEach(exp -> activities.add(OverviewResponse.RecentActivity.builder()
                    .type("experiment")
                    .title(exp.getName())
                    .time(toEpoch(exp.getCreateTime()))
                    .description(exp.getStatus() != null ? exp.getStatus() : "")
                    .build()));
            // dataset
            datasetMapper.selectList(null, 0L, 20)
                .forEach(ds -> activities.add(OverviewResponse.RecentActivity.builder()
                    .type("dataset")
                    .title(ds.getName())
                    .time(toEpoch(ds.getCreateTime()))
                    .description("")
                    .build()));
        } catch (Exception e) {
            log.warn("Failed to query recent activities", e);
        }
        activities.sort((a, b) -> Long.compare(b.getTime(), a.getTime()));
        return activities.size() > 20 ? activities.subList(0, 20) : activities;
    }

    // ──────────────── Doc Index Status ─────────────────────

    private List<OverviewResponse.DocIndexStatus> buildDocIndexStatus() {
        try {
            List<KnowledgeBaseEntity> kbs = knowledgeBaseMapper.selectList(null);
            if (kbs == null || kbs.isEmpty()) return List.of();
            List<OverviewResponse.DocIndexStatus> result = new ArrayList<>();
            for (KnowledgeBaseEntity kb : kbs) {
                Long total = documentMapper.selectCount(
                    new LambdaQueryWrapper<DocumentEntity>()
                        .eq(DocumentEntity::getKbId, kb.getKbId()));
                result.add(OverviewResponse.DocIndexStatus.builder()
                    .kbId(kb.getKbId())
                    .kbName(kb.getName())
                    .totalDocs(total.intValue())
                    .indexedDocs(0)   // TODO: add indexing status when available
                    .progress(0)
                    .build());
            }
            return result;
        } catch (Exception e) {
            log.warn("Failed to query doc index status", e);
            return List.of();
        }
    }

    // ────────────────────── helpers ────────────────────────

    private static long safeCount(Long v) { return v == null ? 0L : v; }

    private static long toEpoch(java.time.LocalDateTime ldt) {
        if (ldt == null) return 0L;
        return ldt.atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli();
    }

}
