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

/**
 * Metadata for a single Prompt version in a diff response.
 * <p>
 * Mirrors fields from {@code prompt_version} that describe the version
 * identity and lifecycle — not the content.
 *
 * @see PromptVersionDiffResult
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class VersionMeta {

	/** Version label (e.g. "v3", "v5"). */
	private String version;

	/** Lifecycle status: {@code "pre"} or {@code "release"}. */
	private String status;

	/** Creation timestamp in epoch milliseconds. */
	private Long createTime;

}
