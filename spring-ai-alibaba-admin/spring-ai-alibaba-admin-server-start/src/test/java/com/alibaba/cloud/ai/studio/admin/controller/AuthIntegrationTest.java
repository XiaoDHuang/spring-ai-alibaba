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

import java.util.List;

import com.alibaba.cloud.ai.studio.runtime.domain.account.LoginRequest;
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
 * Integration test for the authentication flow (critical path #1).
 *
 * Runs against a pre-started Spring Boot backend on localhost:8080.
 * Requires MySQL and Redis running (Docker Compose prod mode).
 */
class AuthIntegrationTest {

	private static final String BASE_URL = "http://localhost:8080";

	private static final RestTemplate restTemplate = new RestTemplate();

	private static final ObjectMapper mapper = new ObjectMapper();

	@BeforeAll
	static void ensureBackendUp() {
		try {
			ResponseEntity<String> h = restTemplate.getForEntity(BASE_URL + "/actuator/health", String.class);
			assertEquals(HttpStatus.OK, h.getStatusCode(), "Backend must be running on localhost:8080");
		}
		catch (Exception e) {
			fail("Backend not reachable: " + e.getMessage());
		}
	}

	private HttpEntity<String> jsonBody(Object obj) throws Exception {
		HttpHeaders h = new HttpHeaders();
		h.setContentType(MediaType.APPLICATION_JSON);
		h.setAccept(List.of(MediaType.APPLICATION_JSON));
		return new HttpEntity<>(mapper.writeValueAsString(obj), h);
	}

	@Test
	@DisplayName("Login with valid credentials returns access_token")
	void shouldLoginSuccessfully() throws Exception {
		LoginRequest req = new LoginRequest();
		req.setUsername("saa");
		req.setPassword("123456");

		ResponseEntity<String> resp = restTemplate.postForEntity(
				BASE_URL + "/console/v1/auth/login", jsonBody(req), String.class);

		assertEquals(HttpStatus.OK, resp.getStatusCode());
		assertNotNull(resp.getBody());
		assertTrue(resp.getBody().contains("access_token"));
		assertTrue(resp.getBody().contains("refresh_token"));
	}

	@Test
	@DisplayName("Login with wrong password returns error")
	void shouldRejectWrongPassword() throws Exception {
		LoginRequest req = new LoginRequest();
		req.setUsername("saa");
		req.setPassword("wrong-password");

		try {
			restTemplate.postForEntity(BASE_URL + "/console/v1/auth/login", jsonBody(req), String.class);
			fail("Expected 4xx for wrong password");
		}
		catch (HttpClientErrorException e) {
			assertTrue(e.getStatusCode().is4xxClientError());
		}
	}

	@Test
	@DisplayName("Protected endpoint accessible with valid JWT")
	void shouldAccessProtectedEndpointWithValidToken() throws Exception {
		LoginRequest loginReq = new LoginRequest();
		loginReq.setUsername("saa");
		loginReq.setPassword("123456");

		ResponseEntity<String> loginResp = restTemplate.postForEntity(
				BASE_URL + "/console/v1/auth/login", jsonBody(loginReq), String.class);

		assertNotNull(loginResp.getBody());
		assertFalse(loginResp.getBody().startsWith("<"),
				"Login returned HTML, not JSON: " + loginResp.getBody().substring(0, Math.min(200, loginResp.getBody().length())));
		String token = mapper.readTree(loginResp.getBody()).at("/data/access_token").asText();
		assertNotNull(token);
		assertFalse(token.isBlank());

		HttpHeaders authHeaders = new HttpHeaders();
		authHeaders.setBearerAuth(token);
		ResponseEntity<String> profileResp = restTemplate.exchange(
				BASE_URL + "/console/v1/accounts/profile",
				HttpMethod.GET,
				new HttpEntity<>(authHeaders),
				String.class);

		assertEquals(HttpStatus.OK, profileResp.getStatusCode());
	}

	@Test
	@DisplayName("Protected endpoint rejects request without token")
	void shouldRejectRequestWithoutToken() {
		try {
			restTemplate.getForEntity(BASE_URL + "/console/v1/accounts/profile", String.class);
			fail("Expected 401 without token");
		}
		catch (HttpClientErrorException e) {
			assertEquals(HttpStatus.UNAUTHORIZED, e.getStatusCode());
		}
	}

}
