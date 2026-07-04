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

import com.alibaba.cloud.ai.studio.admin.dto.PromptVersionDetail;
import com.alibaba.cloud.ai.studio.admin.dto.PromptVersionDiffResult;
import com.alibaba.cloud.ai.studio.admin.entity.PromptVersionDO;
import com.alibaba.cloud.ai.studio.admin.exception.StudioException;
import com.alibaba.cloud.ai.studio.admin.mapper.PromptMapper;
import com.alibaba.cloud.ai.studio.admin.mapper.PromptVersionMapper;
import com.alibaba.cloud.ai.studio.admin.service.PromptService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Unit tests for {@link PromptVersionServiceImpl#diffVersions}.
 * <p>
 * Covers the key boundary scenarios from the requirements document
 * (section 4 of prompt-version-diff.md).
 * Uses Mockito to mock mapper layer — no DB or Testcontainers needed.
 */
@ExtendWith(MockitoExtension.class)
class PromptVersionServiceDiffTest {

	@Mock
	private PromptVersionMapper promptVersionMapper;

	@Mock
	private PromptMapper promptMapper;

	@Mock
	private PromptService promptService;

	@Mock
	private ObjectMapper objectMapper;

	@Mock
	private NacosClientService nacosClientService;

	@InjectMocks
	private PromptVersionServiceImpl service;

	private static final String PROMPT_KEY = "test-prompt";
	private static final String VERSION_V1 = "v1";
	private static final String VERSION_V2 = "v2";

	private PromptVersionDO makeDO(String version, String template, String variables, String modelConfig) {
		return PromptVersionDO.builder()
			.id(10001L)
			.promptKey(PROMPT_KEY)
			.version(version)
			.versionDesc("desc-" + version)
			.template(template)
			.variables(variables)
			.modelConfig(modelConfig)
			.status("release")
			.previousVersion(null)
			.createTime(LocalDateTime.of(2026, 7, 1, 12, 0, 0))
			.build();
	}

	@BeforeEach
	void resetMocks() {
		reset(promptVersionMapper, promptMapper, promptService, objectMapper, nacosClientService);
	}

	// =====================================================================
	// E01 — versionA == versionB
	// =====================================================================

	@Test
	@DisplayName("E01: versionA == versionB → throws StudioException(INVALID_PARAM)")
	void shouldRejectSameVersion() {
		StudioException ex = assertThrows(StudioException.class, () -> {
			service.diffVersions(PROMPT_KEY, "v1", "v1");
		});

		assertEquals(StudioException.INVALID_PARAM, ex.getErrCode(),
				"error code is INVALID_PARAM (400)");
		assertEquals("versionA 和 versionB 不能相同", ex.getErrMsg(),
				"error message matches the implementation");
		// No mapper calls — parameter validation happens before any DB access
		verifyNoInteractions(promptVersionMapper, promptMapper, promptService,
				objectMapper, nacosClientService);
	}

	// =====================================================================
	// E02 — versionA not found
	// =====================================================================

	@Test
	@DisplayName("E02: versionA not found → throws StudioException(NOT_FOUND) with version in message")
	void shouldThrowNotFoundWhenVersionAMissing() {
		when(promptVersionMapper.selectByPromptKeyAndVersion(PROMPT_KEY, "v99"))
			.thenReturn(null);

		StudioException ex = assertThrows(StudioException.class, () -> {
			service.diffVersions(PROMPT_KEY, "v99", VERSION_V1);
		});

		assertEquals(StudioException.NOT_FOUND, ex.getErrCode(),
				"error code is NOT_FOUND (404)");
		// Actual message format from getByPromptKeyAndVersion:
		// "Prompt版本不存在: {promptKey}@{version}"
		assertEquals("Prompt版本不存在: " + PROMPT_KEY + "@v99", ex.getErrMsg(),
				"error message is the same as getByPromptKeyAndVersion — "
						+ "formatted as 'Prompt版本不存在: {key}@{version}'");
		// versionB is never fetched because versionA fails first
		verify(promptVersionMapper).selectByPromptKeyAndVersion(PROMPT_KEY, "v99");
		verifyNoMoreInteractions(promptVersionMapper);
		verifyNoInteractions(promptMapper, promptService, objectMapper, nacosClientService);
	}

	// =====================================================================
	// E04 — template is null → valueA/valueB return "", changed=false
	// =====================================================================

	@Test
	@DisplayName("E04: template is null in both versions → valueA/valueB='', changed=false")
	void shouldTreatNullTemplateAsEmptyString() throws StudioException {
		// Both versions have template=null
		PromptVersionDO doA = makeDO(VERSION_V1, null /* template */, "[\"x\"]", "{}");
		PromptVersionDO doB = makeDO(VERSION_V2, null /* template */, "[\"x\"]", "{}");

		when(promptVersionMapper.selectByPromptKeyAndVersion(PROMPT_KEY, VERSION_V1))
			.thenReturn(doA);
		when(promptVersionMapper.selectByPromptKeyAndVersion(PROMPT_KEY, VERSION_V2))
			.thenReturn(doB);

		PromptVersionDiffResult result = service.diffVersions(PROMPT_KEY, VERSION_V1, VERSION_V2);

		// E04: null → "" (D1 decision), two empty strings are equal → changed=false
		assertEquals("", result.getDiffs().getTemplate().getValueA(),
				"null template → valueA is ''");
		assertEquals("", result.getDiffs().getTemplate().getValueB(),
				"null template → valueB is ''");
		assertFalse(result.getDiffs().getTemplate().getChanged(),
				"two empty strings are equal → changed=false");

		// variables are identical → changed=false
		assertFalse(result.getDiffs().getVariables().getChanged());
		assertEquals("[\"x\"]", result.getDiffs().getVariables().getValueA());

		// modelConfig identical → changed=false
		assertFalse(result.getDiffs().getModelConfig().getChanged());
	}

	// =====================================================================
	// Happy path — templates differ, variables same
	// =====================================================================

	@Test
	@DisplayName("Happy path: different templates → changed=true; same variables → changed=false")
	void shouldDetectDifferencesCorrectly() throws StudioException {
		PromptVersionDO doA = makeDO(VERSION_V1,
				"You are a helpful assistant.\nAnswer: {{q}}",
				"[\"q\"]",
				"{\"temperature\":0.7}");
		PromptVersionDO doB = makeDO(VERSION_V2,
				"You are a professional assistant.\nAnswer: {{q}}\nKeep it short.",
				"[\"q\"]",
				"{\"temperature\":0.3}");

		when(promptVersionMapper.selectByPromptKeyAndVersion(PROMPT_KEY, VERSION_V1))
			.thenReturn(doA);
		when(promptVersionMapper.selectByPromptKeyAndVersion(PROMPT_KEY, VERSION_V2))
			.thenReturn(doB);

		PromptVersionDiffResult result = service.diffVersions(PROMPT_KEY, VERSION_V1, VERSION_V2);

		// ── template: different → changed=true ──
		assertTrue(result.getDiffs().getTemplate().getChanged(),
				"templates differ → changed=true");
		assertEquals("You are a helpful assistant.\nAnswer: {{q}}",
				result.getDiffs().getTemplate().getValueA(),
				"valueA is the raw template from version v1");
		assertEquals("You are a professional assistant.\nAnswer: {{q}}\nKeep it short.",
				result.getDiffs().getTemplate().getValueB(),
				"valueB is the raw template from version v2");

		// ── variables: identical → changed=false ──
		assertFalse(result.getDiffs().getVariables().getChanged(),
				"variables are identical → changed=false");
		assertEquals("[\"q\"]", result.getDiffs().getVariables().getValueA());
		assertEquals("[\"q\"]", result.getDiffs().getVariables().getValueB());

		// ── modelConfig: different → changed=true ──
		assertTrue(result.getDiffs().getModelConfig().getChanged(),
				"modelConfig differs → changed=true");
		assertEquals("{\"temperature\":0.7}", result.getDiffs().getModelConfig().getValueA());
		assertEquals("{\"temperature\":0.3}", result.getDiffs().getModelConfig().getValueB());

		// ── metadata ──
		assertEquals(PROMPT_KEY, result.getPromptKey());
		assertEquals(VERSION_V1, result.getVersionA().getVersion());
		assertEquals(VERSION_V2, result.getVersionB().getVersion());
		assertEquals("release", result.getVersionA().getStatus());
		assertNotNull(result.getVersionA().getCreateTime());
	}

	// =====================================================================
	// Blank param validation
	// =====================================================================

	@Test
	@DisplayName("Blank promptKey → throws StudioException(INVALID_PARAM)")
	void shouldRejectBlankPromptKey() {
		StudioException ex = assertThrows(StudioException.class, () -> {
			service.diffVersions("  ", VERSION_V1, VERSION_V2);
		});
		assertEquals(StudioException.INVALID_PARAM, ex.getErrCode());
		assertEquals("参数错误：promptKey 不能为空", ex.getErrMsg());
	}

	@Test
	@DisplayName("Null versionA → throws StudioException(INVALID_PARAM)")
	void shouldRejectNullVersionA() {
		StudioException ex = assertThrows(StudioException.class, () -> {
			service.diffVersions(PROMPT_KEY, null, VERSION_V2);
		});
		assertEquals(StudioException.INVALID_PARAM, ex.getErrCode());
		assertEquals("参数错误：versionA 不能为空", ex.getErrMsg());
	}

}
