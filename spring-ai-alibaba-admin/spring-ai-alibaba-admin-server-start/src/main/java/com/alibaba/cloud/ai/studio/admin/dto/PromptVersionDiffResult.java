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
 * Result of comparing two Prompt versions.
 * <p>
 * Returned by {@code GET /api/prompt/version/diff}. Contains version
 * metadata for both sides and per-field diff items for the three
 * comparable fields: template, variables, modelConfig.
 *
 * @see VersionMeta
 * @see DiffItem
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PromptVersionDiffResult {

	/** The Prompt key being compared. */
	private String promptKey;

	/** Metadata for version A. */
	private VersionMeta versionA;

	/** Metadata for version B. */
	private VersionMeta versionB;

	/** Per-field diff results. */
	private DiffFields diffs;

	// ──────────────────────────────────────────────
	// Inner type: DiffFields
	// ──────────────────────────────────────────────

	/**
	 * Holds the three {@link DiffItem} comparisons between two versions.
	 */
	@Data
	@Builder
	@NoArgsConstructor
	@AllArgsConstructor
	public static class DiffFields {

		/** Prompt template content comparison. */
		private DiffItem template;

		/** Variables JSON comparison. */
		private DiffItem variables;

		/** Model config JSON comparison. */
		private DiffItem modelConfig;

	}

}
