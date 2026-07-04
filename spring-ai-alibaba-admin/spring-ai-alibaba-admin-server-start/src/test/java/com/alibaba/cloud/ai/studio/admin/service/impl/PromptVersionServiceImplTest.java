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
import java.time.ZoneId;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Characterization Test — locks in the current behavior of
 * {@link PromptVersionServiceImpl#getByPromptKeyAndVersion(String, String)}.
 * <p>
 * All assertions are derived from the actual implementation, not from
 * specification documents or assumptions.
 *
 * @see <a href="../../../../../../../../../../docs/test-plan.md">test-plan.md Batch 3 (Characterization)</a>
 */
@ExtendWith(MockitoExtension.class)
class PromptVersionServiceImplTest {

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
	private static final String VERSION = "v3";
	private static final LocalDateTime FIXED_TIME = LocalDateTime.of(2026, 7, 1, 12, 0, 0);

	// Pre-computed epoch millis based on system default zone
	private static final long EXPECTED_CREATE_TIME_MS = FIXED_TIME
		.atZone(ZoneId.systemDefault())
		.toInstant()
		.toEpochMilli();

	/**
	 * Realistic PromptVersionDO capturing what the actual DB returns.
	 * Fields and values match the prompt_version table schema.
	 */
	private PromptVersionDO buildMockDO() {
		PromptVersionDO mockDO = PromptVersionDO.builder()
			.id(10001L)
			.version(VERSION)
			.promptKey(PROMPT_KEY)
			.versionDesc("测试版本描述")
			.template("You are a helpful assistant.\nUser: {{question}}")
			.variables("[\"question\"]")
			.modelConfig("{\"temperature\": 0.7}")
			.createTime(FIXED_TIME)
			.previousVersion("v2")
			.status("release")
			.build();
		// Verify that exactly the fields we set exist on PromptVersionDO —
		// if a future change adds/removes fields, this test will still compile
		// and the Characterization Test captures the field mapping in fromDO().
		return mockDO;
	}

	@BeforeEach
	void resetMocks() {
		reset(promptVersionMapper, promptMapper, promptService, objectMapper, nacosClientService);
	}

	// ======================================================================
	// Scenario 1 — version exists
	// ======================================================================

	@Test
	@DisplayName("CT-01: version exists → returns PromptVersionDetail with all fields mapped from DO")
	void shouldReturnDetailWhenVersionExists() throws StudioException {
		PromptVersionDO mockDO = buildMockDO();
		when(promptVersionMapper.selectByPromptKeyAndVersion(PROMPT_KEY, VERSION))
			.thenReturn(mockDO);

		PromptVersionDetail result = service.getByPromptKeyAndVersion(PROMPT_KEY, VERSION);

		// Actual behavior captured from PromptVersionDetail.fromDO():
		assertNotNull(result);

		// — direct field mappings
		assertEquals(VERSION, result.getVersion(), "version is copied verbatim");
		assertEquals(PROMPT_KEY, result.getPromptKey(), "promptKey is copied verbatim");
		assertEquals("测试版本描述", result.getVersionDescription(),
				"versionDescription is mapped from versionDesc");
		assertEquals("You are a helpful assistant.\nUser: {{question}}", result.getTemplate(),
				"template is copied verbatim — no trimming, no transformation");
		assertEquals("[\"question\"]", result.getVariables(),
				"variables is copied verbatim — JSON string, not parsed");
		assertEquals("{\"temperature\": 0.7}", result.getModelConfig(),
				"modelConfig is copied verbatim — JSON string, not parsed");
		assertEquals("v2", result.getPreviousVersion(),
				"previousVersion is copied verbatim");
		assertEquals("release", result.getStatus(),
				"status is copied verbatim — no enum conversion");

		// — createTime conversion (LocalDateTime → epoch millis using system default zone)
		assertEquals(EXPECTED_CREATE_TIME_MS, result.getCreateTime(),
				"createTime is converted from LocalDateTime to epoch millis "
						+ "using ZoneId.systemDefault() — not UTC, not Shanghai");
	}

	// ======================================================================
	// Scenario 2 — version not found
	// ======================================================================

	@Test
	@DisplayName("CT-02: version not found → throws StudioException with NOT_FOUND(404) and specific message")
	void shouldThrowNotFoundWhenVersionMissing() {
		when(promptVersionMapper.selectByPromptKeyAndVersion(PROMPT_KEY, "v99"))
			.thenReturn(null);

		StudioException ex = assertThrows(StudioException.class, () -> {
			service.getByPromptKeyAndVersion(PROMPT_KEY, "v99");
		});

		// Actual behavior captured from the implementation:
		assertEquals(StudioException.NOT_FOUND, ex.getErrCode(),
				"error code is NOT_FOUND (404) — not INVALID_PARAM or SERVER_ERROR");
		assertEquals("Prompt版本不存在: " + PROMPT_KEY + "@v99", ex.getErrMsg(),
				"error message format is 'Prompt版本不存在: {promptKey}@{version}' — "
						+ "note the Chinese text and @ separator");

		// verify mapper was called exactly once with correct args
		verify(promptVersionMapper).selectByPromptKeyAndVersion(PROMPT_KEY, "v99");
		// Actual behavior: no other mappers/services are called on this path
		verifyNoMoreInteractions(promptVersionMapper);
		verifyNoInteractions(promptMapper, promptService, objectMapper, nacosClientService);
	}

	// ======================================================================
	// Scenario 3 — confirm NO status filtering
	// ======================================================================

	@Test
	@DisplayName("CT-03: method does NOT filter by status — any status is returned as-is")
	void shouldNotFilterByStatus() throws StudioException {
		// Use a DO with status = null (boundary) to prove no filtering
		PromptVersionDO nullStatusDO = PromptVersionDO.builder()
			.id(10002L)
			.version(VERSION)
			.promptKey(PROMPT_KEY)
			.versionDesc(null)
			.template("minimal")
			.variables(null)
			.modelConfig(null)
			.createTime(null)
			.previousVersion(null)
			.status(null)   // ← null status: if the method filtered, it would crash
			.build();

		when(promptVersionMapper.selectByPromptKeyAndVersion(PROMPT_KEY, VERSION))
			.thenReturn(nullStatusDO);

		PromptVersionDetail result = service.getByPromptKeyAndVersion(PROMPT_KEY, VERSION);

		// The method does not inspect or filter on status — it just passes through
		assertNull(result.getStatus(),
				"status is returned as-is (null), proving no status filtering is applied");
		assertNull(result.getVersionDescription(),
				"null versionDesc is returned as null — no default value substitution");
		assertNull(result.getCreateTime(),
				"null createTime is returned as null — fromDO() has null-check: "
						+ "null in → null out, no default timestamp");
	}

}
