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
 * A single field's diff result between two Prompt versions.
 * <p>
 * Backend returns raw string values and a {@code changed} flag.
 * Frontend is responsible for line-level / word-level highlight rendering.
 * <p>
 * <b>Null handling (D1 decision):</b> when the underlying DB field is
 * {@code null}, {@link #valueA} / {@link #valueB} are returned as
 * empty string {@code ""}, and {@link #changed} is computed against
 * the empty string.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class DiffItem {

	/** Whether the field differs between version A and version B. */
	private Boolean changed;

	/** Raw string value from version A (null → ""). */
	private String valueA;

	/** Raw string value from version B (null → ""). */
	private String valueB;

}
