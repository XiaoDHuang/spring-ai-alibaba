package com.alibaba.cloud.ai.studio.admin.service.impl;

import com.alibaba.cloud.ai.studio.admin.common.PageResult;
import com.alibaba.cloud.ai.studio.admin.dto.DiffItem;
import com.alibaba.cloud.ai.studio.admin.dto.PromptVersion;
import com.alibaba.cloud.ai.studio.admin.dto.PromptVersionDetail;
import com.alibaba.cloud.ai.studio.admin.dto.PromptVersionDiffResult;
import com.alibaba.cloud.ai.studio.admin.dto.VersionMeta;
import com.alibaba.cloud.ai.studio.admin.dto.request.PromptVersionCreateRequest;
import com.alibaba.cloud.ai.studio.admin.dto.request.PromptVersionListRequest;
import com.alibaba.cloud.ai.studio.admin.entity.PromptVersionDO;
import com.alibaba.cloud.ai.studio.admin.exception.StudioException;
import com.alibaba.cloud.ai.studio.admin.mapper.PromptMapper;
import com.alibaba.cloud.ai.studio.admin.mapper.PromptVersionMapper;
import com.alibaba.cloud.ai.studio.admin.service.PromptService;
import com.alibaba.cloud.ai.studio.admin.service.PromptVersionService;
import com.alibaba.nacos.api.config.ConfigService;
import com.alibaba.nacos.api.exception.NacosException;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Objects;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class PromptVersionServiceImpl implements PromptVersionService {
    
    private final PromptVersionMapper promptVersionMapper;
    
    private final PromptMapper promptMapper;
    
    private final PromptService promptService;
    
    private final ObjectMapper objectMapper;
    
    private final NacosClientService nacosClientService;
    
    @Override
    @Transactional
    public PromptVersion create(PromptVersionCreateRequest request) throws StudioException {
        log.info("创建Prompt版本: {}", request);
        
        // 1. 首先验证对应的Prompt是否存在
        if (promptMapper.selectByPromptKey(request.getPromptKey()) == null) {
            throw new StudioException(StudioException.NOT_FOUND,
                    String.format("Prompt不存在，promptKey: %s，请先创建对应的Prompt", request.getPromptKey()));
        }
        
        // 2. 检查版本是否已存在及状态验证
        boolean exists = promptVersionMapper.existsByPromptKeyAndVersion(request.getPromptKey(), request.getVersion());
        if (exists) {
            // 如果版本已存在，检查状态
            String existingStatus = promptVersionMapper.selectStatusByPromptKeyAndVersion(request.getPromptKey(),
                    request.getVersion());
            
            // 如果要发布预发布版本，但已存在正式版本，则拦截
            if ("pre".equals(request.getStatus()) && "release".equals(existingStatus)) {
                throw new StudioException(StudioException.CONFLICT,
                        String.format("版本 %s 已经是正式版本(release)，不能再创建同版本的预发布版本",
                                request.getVersion()));
            }
            
            // 如果要发布正式版本，但已存在正式版本，则拦截
            if ("release".equals(request.getStatus()) && "release".equals(existingStatus)) {
                throw new StudioException(StudioException.CONFLICT,
                        String.format("版本 %s 已经是正式版本(release)，不能重复发布", request.getVersion()));
            }
            
            // 如果要发布预发布版本，且已存在预发布版本，则允许（会覆盖原有预发布版本）
            if ("pre".equals(request.getStatus()) && "pre".equals(existingStatus)) {
                log.info("版本 {} 已存在预发布版本，将覆盖原有预发布版本", request.getVersion());
                
                // 获取前一个版本
                String previousVersion = promptVersionMapper.selectLatestVersion(request.getPromptKey());
                
                // 构建更新的版本实体
                PromptVersionDO updatePromptVersionDO = PromptVersionDO.builder().version(request.getVersion())
                        .promptKey(request.getPromptKey()).versionDesc(request.getVersionDescription())
                        .template(request.getTemplate()).variables(request.getVariables())
                        .modelConfig(request.getModelConfig()).status(request.getStatus())
                        .previousVersion(previousVersion).build();
                
                // 更新已存在的预发布版本
                promptVersionMapper.updateByPromptKeyAndVersion(updatePromptVersionDO);
                log.info("Prompt预发布版本更新成功: {} - {}", request.getPromptKey(), request.getVersion());
                
                // 重新查询更新后的版本详情返回
                PromptVersionDO updatedVersion = promptVersionMapper.selectByPromptKeyAndVersion(request.getPromptKey(),
                        request.getVersion());
                return PromptVersion.fromDO(updatedVersion);
            }
        }
        
        // 获取前一个版本
        String previousVersion = promptVersionMapper.selectLatestVersion(request.getPromptKey());
        
        PromptVersionDO promptVersionDO = PromptVersionDO.builder().version(request.getVersion())
                .promptKey(request.getPromptKey()).versionDesc(request.getVersionDescription())
                .template(request.getTemplate()).variables(request.getVariables()).modelConfig(request.getModelConfig())
                .status(request.getStatus()).previousVersion(previousVersion).build();
        
        promptVersionMapper.insert(promptVersionDO);
        log.info("Prompt版本创建成功: {}", promptVersionDO.getId());
        if ("release".equals(request.getStatus())) {
            publishPromptToNacos(request);
        }
        
        // 更新Prompt的最新版本
        promptService.updateLatestVersion(request.getPromptKey(), request.getVersion());
        
        return PromptVersion.fromDO(promptVersionDO);
    }
    
    public void publishPromptToNacos(PromptVersionCreateRequest request) {
        try {
            ConfigService configService = nacosClientService.getConfigService();
            String dataId = "prompt-" + request.getPromptKey() + ".json";
            String group = "nacos-ai-meta";
            NacosPrompt nacosPrompt = new NacosPrompt();
            nacosPrompt.setPromptKey(request.getPromptKey());
            nacosPrompt.setVersion(request.getVersion());
            nacosPrompt.setTemplate(request.getTemplate());
            nacosPrompt.setVariables(request.getVariables());
            boolean success = configService.publishConfig(dataId, group, objectMapper.writeValueAsString(nacosPrompt));
            if (!success) {
                log.error("同步 Prompt {} 版本 {} 到 Nacos 失败", request.getPromptKey(), request.getVersion());
            } else {
                log.info("同步 Prompt {} 版本 {} 到 Nacos 成功", request.getPromptKey(), request.getVersion());
            }
        } catch (NacosException e) {
            log.error("同步 Prompt {} 版本 {} 到 Nacos 失败", request.getPromptKey(), request.getVersion(), e);
        } catch (JsonProcessingException e) {
            log.error("同步 Nacos 时 序列化 Prompt {} 版本 {} 失败", request.getPromptKey(), request.getVersion(), e);
        }
    }
    
    @Override
    public PromptVersionDetail getByPromptKeyAndVersion(String promptKey, String version) throws StudioException {
        log.info("查询Prompt版本详情: promptKey={}, version={}", promptKey, version);
        
        PromptVersionDO promptVersionDO = promptVersionMapper.selectByPromptKeyAndVersion(promptKey, version);
        if (promptVersionDO == null) {
            throw new StudioException(StudioException.NOT_FOUND, "Prompt版本不存在: " + promptKey + "@" + version);
        }
        
        return PromptVersionDetail.fromDO(promptVersionDO);
    }

    @Override
    public PromptVersionDiffResult diffVersions(String promptKey, String versionA, String versionB)
            throws StudioException {
        // ── 参数校验 ──
        if (promptKey == null || promptKey.isBlank()) {
            throw new StudioException(StudioException.INVALID_PARAM, "参数错误：promptKey 不能为空");
        }
        if (versionA == null || versionA.isBlank()) {
            throw new StudioException(StudioException.INVALID_PARAM, "参数错误：versionA 不能为空");
        }
        if (versionB == null || versionB.isBlank()) {
            throw new StudioException(StudioException.INVALID_PARAM, "参数错误：versionB 不能为空");
        }
        if (versionA.equals(versionB)) {
            throw new StudioException(StudioException.INVALID_PARAM, "versionA 和 versionB 不能相同");
        }

        // ── 查两版本（复用 getByPromptKeyAndVersion，已确认无 metrics 副作用）──
        PromptVersionDetail detailA = getByPromptKeyAndVersion(promptKey, versionA);
        PromptVersionDetail detailB = getByPromptKeyAndVersion(promptKey, versionB);

        // ── null → ""（D1 决策）──
        String templateA = nullToEmpty(detailA.getTemplate());
        String templateB = nullToEmpty(detailB.getTemplate());
        String varsA = nullToEmpty(detailA.getVariables());
        String varsB = nullToEmpty(detailB.getVariables());
        String configA = nullToEmpty(detailA.getModelConfig());
        String configB = nullToEmpty(detailB.getModelConfig());

        // ── DiffItem × 3 ──
        DiffItem templateDiff = DiffItem.builder()
            .changed(!Objects.equals(templateA, templateB))
            .valueA(templateA).valueB(templateB).build();
        DiffItem variablesDiff = DiffItem.builder()
            .changed(!Objects.equals(varsA, varsB))
            .valueA(varsA).valueB(varsB).build();
        DiffItem modelConfigDiff = DiffItem.builder()
            .changed(!Objects.equals(configA, configB))
            .valueA(configA).valueB(configB).build();

        // ── DiffFields ──
        PromptVersionDiffResult.DiffFields diffs = PromptVersionDiffResult.DiffFields.builder()
            .template(templateDiff)
            .variables(variablesDiff)
            .modelConfig(modelConfigDiff)
            .build();

        // ── VersionMeta × 2 ──
        VersionMeta metaA = VersionMeta.builder()
            .version(detailA.getVersion())
            .status(detailA.getStatus())
            .createTime(detailA.getCreateTime())
            .build();
        VersionMeta metaB = VersionMeta.builder()
            .version(detailB.getVersion())
            .status(detailB.getStatus())
            .createTime(detailB.getCreateTime())
            .build();

        return PromptVersionDiffResult.builder()
            .promptKey(promptKey)
            .versionA(metaA)
            .versionB(metaB)
            .diffs(diffs)
            .build();
    }

    private static String nullToEmpty(String s) {
        return s == null ? "" : s;
    }

    @Override
    public PageResult<PromptVersion> list(PromptVersionListRequest request) {
        log.info("查询Prompt版本列表: {}", request);
        
        int offset = (request.getPageNo() - 1) * request.getPageSize();
        
        List<PromptVersionDO> promptVersionDOList = promptVersionMapper.selectListByPromptKey(request.getPromptKey(),
                request.getStatus(), offset, request.getPageSize());
        
        int totalCount = promptVersionMapper.selectCountByPromptKey(request.getPromptKey(), request.getStatus());
        
        List<PromptVersion> promptVersionList = promptVersionDOList.stream().map(PromptVersion::fromDO)
                .collect(Collectors.toList());
        
        return new PageResult<>((long) totalCount, (long) request.getPageNo(), (long) request.getPageSize(),
                promptVersionList);
    }
    
    
    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public static class NacosPrompt {
        
        private String promptKey;
        
        private String version;
        
        private String template;
        
        private String variables;
    }
}
