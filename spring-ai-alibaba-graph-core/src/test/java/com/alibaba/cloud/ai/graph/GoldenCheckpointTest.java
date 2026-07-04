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
package com.alibaba.cloud.ai.graph;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.alibaba.cloud.ai.graph.checkpoint.config.SaverConfig;
import com.alibaba.cloud.ai.graph.checkpoint.savers.MemorySaver;
import com.alibaba.cloud.ai.graph.state.StateSnapshot;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import static com.alibaba.cloud.ai.graph.StateGraph.END;
import static com.alibaba.cloud.ai.graph.StateGraph.START;
import static com.alibaba.cloud.ai.graph.action.AsyncEdgeAction.edge_async;
import static com.alibaba.cloud.ai.graph.action.AsyncNodeAction.node_async;
import static org.junit.jupiter.api.Assertions.*;

/**
 * Characterization Test (Golden File) for Graph Checkpoint behavior.
 *
 * Captures the current serialization behavior of checkpoint state snapshots
 * as golden JSON files. When refactoring the graph engine, diff against
 * these golden files to detect unintended behavioral changes.
 *
 * Design: first run writes golden files; subsequent runs assert current
 * behavior matches. Golden files are committed to git.
 */
public class GoldenCheckpointTest {

	private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(GoldenCheckpointTest.class);

	private static final Path GOLDEN_DIR = Paths.get("src/test/resources/golden");

	private static ObjectMapper prettyMapper;

	@BeforeAll
	static void setUp() {
		prettyMapper = new ObjectMapper().enable(SerializationFeature.INDENT_OUTPUT)
			.enable(SerializationFeature.ORDER_MAP_ENTRIES_BY_KEYS);
	}

	// ---- helpers ----

	private void assertGolden(String scenario, Object actual) throws IOException {
		String actualJson = prettyMapper.writeValueAsString(actual);
		Path goldenFile = GOLDEN_DIR.resolve("checkpoint-" + scenario + ".json");
		if (!Files.exists(goldenFile)) {
			Files.createDirectories(goldenFile.getParent());
			Files.writeString(goldenFile, actualJson, StandardCharsets.UTF_8);
			log.info("Created golden file: {}", goldenFile);
		}
		else {
			String expected = Files.readString(goldenFile, StandardCharsets.UTF_8);
			assertEquals(expected, actualJson,
					"Golden file mismatch for scenario '" + scenario
							+ "'. If the behavior change is intentional, delete the golden file and re-run.");
		}
	}

	private StateGraph buildLinearGraph() throws Exception {
		KeyStrategyFactory ksf = new KeyStrategyFactoryBuilder().addStrategy("steps")
			.addStrategy("messages", KeyStrategy.APPEND)
			.build();
		return new StateGraph(ksf)
			.addNode("node_a", node_async(state -> {
				int s = (int) state.value("steps").orElse(0);
				return Map.of("steps", s + 1, "messages", "node_a:step:" + (s + 1));
			}))
			.addNode("node_b", node_async(state -> {
				int s = (int) state.value("steps").orElse(0);
				return Map.of("steps", s + 2, "messages", "node_b:step:" + (s + 2));
			}))
			.addEdge(START, "node_a")
			.addEdge("node_a", "node_b")
			.addEdge("node_b", END);
	}

	private StateGraph buildConditionalGraph() throws Exception {
		KeyStrategyFactory ksf = new KeyStrategyFactoryBuilder().addStrategy("messages", KeyStrategy.APPEND)
			.addStrategy("counter")
			.build();
		return new StateGraph(ksf)
			.addNode("agent", node_async(state -> {
				int c = (int) state.value("counter").orElse(0);
				String msg = (c < 2) ? "tool_calls" : "finished";
				return Map.of("counter", c + 1, "messages", msg);
			}))
			.addNode("tools", node_async(state -> Map.of("messages", "tool_result")))
			.addEdge(START, "agent")
			.addConditionalEdges("agent",
					edge_async(state -> state.<List<String>>value("messages")
						.map(msgs -> msgs.get(msgs.size() - 1).equals("tool_calls") ? "tools" : END)
						.orElse(END)),
					Map.of("tools", "tools", END, END))
			.addEdge("tools", "agent");
	}

	// ---- tests ----

	@Test
	void testLinearGraphCheckpointHistory() throws Exception {
		StateGraph workflow = buildLinearGraph();
		var saver = MemorySaver.builder().build();
		var app = workflow
			.compile(CompileConfig.builder().saverConfig(SaverConfig.builder().register(saver).build()).build());

		var config = RunnableConfig.builder().threadId("golden-linear").build();
		var result = app.invoke(Map.of("steps", 0), config);
		assertTrue(result.isPresent());
		assertEquals(3, result.get().value("steps", 0));

		Collection<StateSnapshot> history = app.getStateHistory(config);
		List<Map<String, Object>> captured = new ArrayList<>();
		for (StateSnapshot snap : history) {
			captured.add(Map.of("nodeId", snap.node() != null ? snap.node() : "", "values",
					snap.state() != null ? snapshotValues(snap) : Map.of()));
		}
		assertFalse(captured.isEmpty(), "Should have at least one checkpoint");
		assertGolden("linear-graph-history", captured);
	}

	@Test
	void testConditionalGraphCheckpointHistory() throws Exception {
		StateGraph workflow = buildConditionalGraph();
		var saver = MemorySaver.builder().build();
		var app = workflow
			.compile(CompileConfig.builder().saverConfig(SaverConfig.builder().register(saver).build()).build());

		var config = RunnableConfig.builder().threadId("golden-conditional").build();
		var result = app.invoke(Map.of("counter", 0), config);
		assertTrue(result.isPresent());
		assertEquals(3, result.get().value("counter", 0));

		Collection<StateSnapshot> history = app.getStateHistory(config);
		List<Map<String, Object>> captured = new ArrayList<>();
		for (StateSnapshot snap : history) {
			captured.add(Map.of("nodeId", snap.node() != null ? snap.node() : "", "values",
					snap.state() != null ? snapshotValues(snap) : Map.of()));
		}
		assertFalse(captured.isEmpty());
		assertGolden("conditional-graph-history", captured);
	}

	@Test
	void testInterruptResumeCheckpoint() throws Exception {
		KeyStrategyFactory ksf = new KeyStrategyFactoryBuilder().addStrategy("steps")
			.addStrategy("messages", KeyStrategy.APPEND)
			.build();

		StateGraph workflow = new StateGraph(ksf)
			.addNode("node_a", node_async(state -> {
				int s = (int) state.value("steps").orElse(0);
				return Map.of("steps", s + 1, "messages", "node_a:step:" + (s + 1));
			}))
			.addNode("node_b", node_async(state -> {
				int s = (int) state.value("steps").orElse(0);
				return Map.of("steps", s + 2, "messages", "node_b:step:" + (s + 2));
			}))
			.addEdge(START, "node_a")
			.addEdge("node_a", "node_b")
			.addEdge("node_b", END);

		var saver = MemorySaver.builder().build();
		var app = workflow.compile(CompileConfig.builder()
			.saverConfig(SaverConfig.builder().register(saver).build())
			.interruptBefore("node_b")
			.build());

		var config = RunnableConfig.builder().threadId("golden-interrupt").build();

		// First invocation: interruptBefore("node_b")
		Exception caught = null;
		try {
			app.invoke(Map.of("steps", 0), config);
		}
		catch (Exception e) {
			caught = e;
		}

		// Get the checkpoint created by the interrupt
		StateSnapshot interruptedSnap = app.getState(config);
		assertNotNull(interruptedSnap);
		assertEquals("node_b", interruptedSnap.next());

		// Capture interrupted state
		Map<String, Object> interruptedCapture = new LinkedHashMap<>();
		interruptedCapture.put("exceptionThrown", caught != null);
		interruptedCapture.put("exceptionMessage", caught != null ? caught.getMessage() : "(none)");
		interruptedCapture.put("nodeId", interruptedSnap.node() != null ? interruptedSnap.node() : "");
		interruptedCapture.put("nextNodeId", interruptedSnap.next() != null ? interruptedSnap.next() : "");
		interruptedCapture.put("values", snapshotValues(interruptedSnap));
		assertGolden("interrupt-before-resume", interruptedCapture);

		// Resume
		var resumeResult = app.invoke((Map<String, Object>) null,
				RunnableConfig.builder(config).resume().build());
		assertTrue(resumeResult.isPresent());
		assertEquals(3, resumeResult.get().value("steps", 0));

		// Capture final history
		Collection<StateSnapshot> history = app.getStateHistory(config);
		List<Map<String, Object>> capturedHistory = new ArrayList<>();
		for (StateSnapshot snap : history) {
			capturedHistory.add(
					Map.of("nodeId", snap.node() != null ? snap.node() : "", "values", snapshotValues(snap)));
		}
		assertGolden("interrupt-resume-history", capturedHistory);
	}

	// ---- snapshot value extraction ----

	private Map<String, Object> snapshotValues(StateSnapshot snap) throws Exception {
		// Extract visible state, stripping internal execution IDs that change per run
		Map<String, Object> values = new LinkedHashMap<>();
		if (snap.state() != null) {
			for (String key : snap.state().data().keySet()) {
				if ("_graph_execution_id_".equals(key)) {
					continue; // volatile ID, skip for golden comparison
				}
				snap.state().value(key).ifPresent(v -> values.put(key, v));
			}
		}
		return values;
	}
}
