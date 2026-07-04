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
package com.alibaba.cloud.ai.studio.admin.controller;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Integration test for App create → Chat completions (critical path #2).
 *
 * Runs against a pre-started Spring Boot backend on localhost:8080.
 * Requires MySQL, Redis, and a valid LLM API Key.
 */
class AppChatIntegrationTest {

	private static final String BASE_URL = "http://localhost:8080";

	private static final RestTemplate restTemplate = new RestTemplate();

	private static final ObjectMapper mapper = new ObjectMapper();

	private static String authToken;

	@BeforeAll
	static void setUp() throws Exception {
		ResponseEntity<String> health = restTemplate.getForEntity(BASE_URL + "/actuator/health", String.class);
		assertEquals(HttpStatus.OK, health.getStatusCode(), "Backend must be running");

		HttpHeaders h = new HttpHeaders();
		h.setContentType(MediaType.APPLICATION_JSON);
		h.setAccept(List.of(MediaType.APPLICATION_JSON));
		String loginBody = "{\"username\":\"saa\",\"password\":\"123456\"}";
		ResponseEntity<String> loginResp = restTemplate.postForEntity(
				BASE_URL + "/console/v1/auth/login", new HttpEntity<>(loginBody, h), String.class);

		authToken = mapper.readTree(loginResp.getBody()).at("/data/access_token").asText();
		assertNotNull(authToken);
		assertFalse(authToken.isBlank());
	}

	private HttpHeaders authHeaders() {
		HttpHeaders h = new HttpHeaders();
		h.setContentType(MediaType.APPLICATION_JSON);
		h.setAccept(List.of(MediaType.APPLICATION_JSON));
		h.setBearerAuth(authToken);
		return h;
	}

	private String createApp(String name) throws Exception {
		String body = mapper.writeValueAsString(Map.of(
				"name", name,
				"description", "Integration test app",
				"type", "basic"));
		ResponseEntity<String> resp = restTemplate.postForEntity(
				BASE_URL + "/console/v1/apps", new HttpEntity<>(body, authHeaders()), String.class);
		assertEquals(HttpStatus.OK, resp.getStatusCode(), "Create app should succeed: " + resp.getBody());
		String appId = mapper.readTree(resp.getBody()).at("/data").asText();
		assertNotNull(appId);
		assertFalse(appId.isBlank());
		return appId;
	}

	private void publishApp(String appId) {
		ResponseEntity<String> resp = restTemplate.postForEntity(
				BASE_URL + "/console/v1/apps/" + appId + "/publish",
				new HttpEntity<>("", authHeaders()), String.class);
		assertEquals(HttpStatus.OK, resp.getStatusCode(), "Publish should succeed");
	}

	@Test
	@DisplayName("Create App → Publish → Chat (non-stream) returns JSON")
	void shouldCreateAppAndChatNonStreaming() throws Exception {
		String appId = createApp("test-app-nonstream");
		publishApp(appId);

		String chatBody = mapper.writeValueAsString(Map.of(
				"appId", appId,
				"messages", List.of(Map.of("role", "user", "content", "Hello")),
				"stream", false));
		ResponseEntity<String> chatResp = restTemplate.postForEntity(
				BASE_URL + "/api/v1/apps/chat/completions",
				new HttpEntity<>(chatBody, authHeaders()), String.class);

		assertEquals(HttpStatus.OK, chatResp.getStatusCode());
		assertNotNull(chatResp.getBody());
		assertTrue(chatResp.getBody().contains("choices"),
				"Response should contain 'choices': "
						+ chatResp.getBody().substring(0, Math.min(200, chatResp.getBody().length())));
	}

	@Test
	@DisplayName("Create App + Chat (SSE) receives data chunks")
	void shouldCreateAppAndChatStreaming() throws Exception {
		String appId = createApp("test-app-stream");
		publishApp(appId);

		String chatBody = mapper.writeValueAsString(Map.of(
				"appId", appId,
				"messages", List.of(Map.of("role", "user", "content", "Hi")),
				"stream", true));

		URL url = new URI(BASE_URL + "/api/v1/apps/chat/completions").toURL();
		HttpURLConnection conn = (HttpURLConnection) url.openConnection();
		conn.setRequestMethod("POST");
		conn.setRequestProperty("Content-Type", "application/json");
		conn.setRequestProperty("Accept", "text/event-stream");
		conn.setRequestProperty("Authorization", "Bearer " + authToken);
		conn.setDoOutput(true);
		conn.getOutputStream().write(chatBody.getBytes(StandardCharsets.UTF_8));
		conn.getOutputStream().close();

		assertEquals(200, conn.getResponseCode(), "SSE request should return 200");

		BufferedReader reader = new BufferedReader(
				new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8));
		String line;
		int dataChunks = 0;
		int maxLines = 200;
		while ((line = reader.readLine()) != null && dataChunks < 5 && maxLines-- > 0) {
			if (line.startsWith("data:")) {
				dataChunks++;
			}
		}
		reader.close();
		conn.disconnect();

		assertTrue(dataChunks >= 1, "SSE stream should contain at least 1 data chunk, got " + dataChunks);
	}

	@Test
	@DisplayName("Create App with missing required fields returns 400")
	void shouldRejectAppCreationWithoutName() throws Exception {
		String body = mapper.writeValueAsString(Map.of("description", "no name app"));
		try {
			restTemplate.postForEntity(BASE_URL + "/console/v1/apps",
					new HttpEntity<>(body, authHeaders()), String.class);
			fail("Expected 400 for missing name");
		}
		catch (HttpClientErrorException e) {
			assertEquals(HttpStatus.BAD_REQUEST, e.getStatusCode(), "Missing name should return 400");
		}
	}

}
