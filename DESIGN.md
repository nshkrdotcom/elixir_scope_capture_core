# Design Document: ElixirScope.Capture.Core (elixir_scope_capture_core)

## 1. Purpose & Vision

**Summary:** Provides the core runtime components responsible for capturing raw events from instrumented Elixir code and performing initial, highly efficient buffering. This is the primary API called by AST-transformed code.

**(Greatly Expanded Purpose based on your existing knowledge of ElixirScope and CPG features):**

The `elixir_scope_capture_core` library is the frontline of ElixirScope's runtime data acquisition. Its primary objective is to provide an extremely low-overhead, high-throughput mechanism for instrumented code to report runtime events. These events, once captured, form the basis for all subsequent analysis, debugging, and correlation, including the linkage to static CPG (Code Property Graph) nodes.

This library aims to:
*   **Minimize Instrumentation Overhead:** Ensure that calls from instrumented code are exceptionally fast (sub-microsecond) to minimize impact on application performance. This is achieved through direct process dictionary lookups for context and efficient ring buffer writes.
*   **Provide a Stable Instrumentation API:** Offer a consistent set of functions (primarily in `ElixirScope.Capture.InstrumentationRuntime`) that the `elixir_scope_compiler` will inject into user code.
*   **Enable Contextual Event Capture:** Manage process-local instrumentation context (via `ElixirScope.Capture.Context`), including correlation IDs and call stacks, to enrich captured events.
*   **Implement Efficient Buffering:** Utilize high-performance, lock-free ring buffers (`ElixirScope.Capture.RingBuffer`) for temporary event storage before asynchronous processing by downstream components (like `elixir_scope_capture_pipeline`).
*   **Support Diverse Event Ingestion:** Offer specialized ingestion functions (`ElixirScope.Capture.Ingestor.*`) for common Elixir/Phoenix/Ecto patterns, which then format events for the ring buffer.
*   **Facilitate AST-Runtime Correlation:** Crucially, the `InstrumentationRuntime.ASTReporting` submodule will handle events that include `ast_node_id`s, which are essential for linking runtime behavior back to specific CPG nodes.

The efficiency and reliability of this library are paramount. It directly impacts the feasibility of comprehensive tracing in production environments. The `ast_node_id` passed to its reporting functions (e.g., `report_ast_function_entry_with_node_id`) is the linchpin for connecting dynamic execution data to the static CPG representation managed by `elixir_scope_ast_repo`.

This library will enable:
*   The `elixir_scope_compiler` to inject standardized, low-overhead calls into user code.
*   The capture of a wide variety of runtime events (function calls, returns, exceptions, variable snapshots, custom events) with minimal performance impact.
*   The efficient buffering of these events for asynchronous processing by the `elixir_scope_capture_pipeline`.
*   The propagation of correlation IDs and `ast_node_id`s necessary for advanced debugging and CPG-based analysis.

## 2. Key Responsibilities

This library is responsible for:

*   **Instrumentation API (`InstrumentationRuntime`):**
    *   Defining the public functions called by instrumented code (e.g., `report_function_entry`, `report_function_exit`, `report_ast_variable_snapshot`, `report_phoenix_request_start`).
    *   Handling events with and without explicit `ast_node_id`s.
*   **Process-Local Context (`Context`):**
    *   Managing whether instrumentation is enabled for the current process.
    *   Tracking the current `correlation_id` and call stack for the process.
    *   Providing utilities like `with_instrumentation_disabled/1`.
*   **Event Ingestion (`Ingestor`):**
    *   Providing type-specific ingestion functions (e.g., `ingest_function_call`, `ingest_phoenix_request_start`) that format data into `ElixirScope.Events.t()` structs.
    *   Handling the actual writing of formatted events to a ring buffer.
*   **Ring Buffer (`RingBuffer`):**
    *   Implementing a high-performance, lock-free (or minimally locking) ring buffer for event storage.
    *   Managing buffer overflow strategies (e.g., drop oldest, drop newest).
    *   Providing an API for reading batches of events (used by `elixir_scope_capture_pipeline`).

## 3. Key Modules & Structure

The primary modules within this library will be:

*   `ElixirScope.Capture.InstrumentationRuntime` (Main facade for instrumented code calls)
    *   `ElixirScope.Capture.InstrumentationRuntime.Context`
    *   `ElixirScope.Capture.InstrumentationRuntime.CoreReporting`
    *   `ElixirScope.Capture.InstrumentationRuntime.ASTReporting`
    *   `ElixirScope.Capture.InstrumentationRuntime.PhoenixReporting`
    *   `ElixirScope.Capture.InstrumentationRuntime.EctoReporting`
    *   `ElixirScope.Capture.InstrumentationRuntime.GenServerReporting`
    *   `ElixirScope.Capture.InstrumentationRuntime.DistributedReporting`
    *   `ElixirScope.Capture.InstrumentationRuntime.Performance`
*   `ElixirScope.Capture.Ingestor` (Core event formatting and writing logic, potentially with submodules as in original structure)
    *   `ElixirScope.Capture.Ingestor.Phoenix`
    *   `ElixirScope.Capture.Ingestor.Ecto`
    *   `ElixirScope.Capture.Ingestor.LiveView`
    *   `ElixirScope.Capture.Ingestor.Channel`
    *   `ElixirScope.Capture.Ingestor.GenServer`
    *   `ElixirScope.Capture.Ingestor.Distributed`
*   `ElixirScope.Capture.RingBuffer` (The ring buffer implementation)

### Proposed File Tree:

```
elixir_scope_capture_core/
├── lib/
│   └── elixir_scope/
│       └── capture/
│           ├── instrumentation_runtime.ex # Main facade
│           ├── instrumentation_runtime/   # Submodules for InstrumentationRuntime
│           │   ├── context.ex
│           │   ├── core_reporting.ex
│           │   ├── ast_reporting.ex
│           │   ├── phoenix_reporting.ex
│           │   ├── ecto_reporting.ex
│           │   ├── genserver_reporting.ex
│           │   └── ...
│           ├── ingestor.ex              # Main Ingestor, delegates or contains logic
│           ├── ingestor/                # Optional submodules for Ingestor
│           │   ├── phoenix.ex
│           │   └── ...
│           └── ring_buffer.ex
├── mix.exs
├── README.md
├── DESIGN.MD
└── test/
    ├── test_helper.exs
    └── elixir_scope/
        └── capture/
            ├── instrumentation_runtime_test.exs
            ├── context_test.exs
            ├── ingestor_test.exs
            └── ring_buffer_test.exs
```

**(Greatly Expanded - Module Description):**
*   **`ElixirScope.Capture.InstrumentationRuntime`**: This is the primary public API for code that has been transformed by `elixir_scope_compiler`. It will contain a comprehensive set of `report_*` functions for various event types. Each function will perform a quick check via `Context.enabled?()`, and if enabled, retrieve the current context (buffer, correlation ID) and delegate the actual event creation and buffering to the `ElixirScope.Capture.Ingestor` or directly to the `RingBuffer` for ultra-hot paths.
    *   **`ElixirScope.Capture.InstrumentationRuntime.Context`**: Manages the process dictionary state (`:elixir_scope_context`, `:elixir_scope_call_stack`). Provides functions to initialize, clear, enable/disable context, and manage correlation IDs and call stacks for the current process. It will also provide the `get_buffer()` mechanism, likely by reading a `:persistent_term` set by the `PipelineManager` or main application.
    *   **`ElixirScope.Capture.InstrumentationRuntime.*Reporting` modules**: These will be thin wrappers or direct implementations that call the `Ingestor` with the correct event type and data, specific to their domain (Core, AST, Phoenix, etc.). They handle the logic of extracting necessary information from their arguments to pass to the `Ingestor`.
*   **`ElixirScope.Capture.Ingestor`**: This module (and its submodules) is responsible for taking raw data from the `InstrumentationRuntime` functions, constructing a fully-formed `ElixirScope.Events.t()` struct (using `ElixirScope.Events.new_event/3`), and writing it to the `RingBuffer`. It handles data truncation and ensures event consistency.
*   **`ElixirScope.Capture.RingBuffer`**: A high-performance, ETS-based (or using `:atomics` for pointers and ETS for data) ring buffer implementation. It provides `write/2` for the `Ingestor` and `read_batch/3` for `elixir_scope_capture_pipeline`. It manages buffer full conditions based on its configured overflow strategy.

## 4. Public API (Conceptual)

The most critical public APIs are:

*   **`ElixirScope.Capture.InstrumentationRuntime` functions (numerous, examples):**
    *   `report_function_entry(module :: module(), function :: atom(), args :: list()) :: correlation_id :: term() | nil`
    *   `report_function_exit(correlation_id :: term(), return_value :: any(), duration_ns :: non_neg_integer()) :: :ok`
    *   `report_ast_function_entry_with_node_id(module :: module(), function :: atom(), args :: list(), correlation_id :: term(), ast_node_id :: String.t()) :: :ok`
    *   `report_ast_variable_snapshot(correlation_id :: term(), variables :: map(), line :: non_neg_integer(), ast_node_id :: String.t()) :: :ok`
    *   (All other `report_*` functions for Phoenix, Ecto, etc. as defined in the original codebase)
*   **`ElixirScope.Capture.Context` functions (for setup and control):**
    *   `initialize_context() :: :ok` (typically called by process startup hooks or supervisors)
    *   `enabled?() :: boolean()`
    *   `current_correlation_id() :: term() | nil`
*   **`ElixirScope.Capture.RingBuffer` functions (for `PipelineManager` interaction):**
    *   `new(opts :: keyword()) :: {:ok, ElixirScope.Capture.RingBuffer.t()} | {:error, term()}`
    *   `read_batch(buffer :: ElixirScope.Capture.RingBuffer.t(), start_position :: non_neg_integer(), count :: pos_integer()) :: {events :: [ElixirScope.Events.t()], new_position :: non_neg_integer()}`
    *   `stats(buffer :: ElixirScope.Capture.RingBuffer.t()) :: map()`

## 5. Core Data Structures

*   **`ElixirScope.Capture.RingBuffer.t()` (Internal Struct):**
    ```elixir
    defmodule ElixirScope.Capture.RingBuffer do
      @type t :: %__MODULE__{
              id: atom(),                     # Unique ID for the buffer instance
              size: pos_integer(),            # Power of 2
              mask: non_neg_integer(),
              overflow_strategy: :drop_oldest | :drop_newest | :block,
              atomics_ref: :atomics.atomics_ref(), # For write_pos, read_pos, counters
              buffer_table: :ets.tab()         # ETS table holding the actual events
            }
      defstruct [:id, :size, :mask, :overflow_strategy, :atomics_ref, :buffer_table]
      # ...
    end
    ```
*   **`ElixirScope.Capture.Context.State.t()` (Internal Process Dictionary Value):**
    ```elixir
    # Implicitly defined by how Process.put/get is used in Context module
    # %{
    #   buffer: ElixirScope.Capture.RingBuffer.t() | nil,
    #   correlation_id: term() | nil, # The *root* correlation ID for the current trace in this process
    #   call_stack: [term()],         # Stack of correlation IDs for nested calls
    #   enabled: boolean()
    # }
    ```
*   Consumes: `ElixirScope.Events.t()` (from `elixir_scope_events`)

## 6. Dependencies

This library will depend on the following ElixirScope libraries:

*   `elixir_scope_utils` (for timestamps, ID generation, data truncation)
*   `elixir_scope_config` (to get configuration for buffer sizes, enabled status, etc.)
*   `elixir_scope_events` (to create and understand the event structs it's buffering)

It will depend on Elixir core libraries (`System`, `Process`, `:atomics`, `:ets`).

## 7. Role in TidewaveScope & Interactions

Within the `TidewaveScope` ecosystem, the `elixir_scope_capture_core` library will:

*   Be the direct interface for any code instrumented by `elixir_scope_compiler`.
*   Be initialized (specifically `Context.initialize_context()` and the setup of the global ring buffer reference) by the main `TidewaveScope` application or its `PipelineManager`.
*   Have its `RingBuffer` instances read by workers in the `elixir_scope_capture_pipeline` library.
*   The `ast_node_id`s passed to its `InstrumentationRuntime.ASTReporting` functions are critical; these IDs originate from the `elixir_scope_compiler` (which itself gets them from `elixir_scope_ast_repo`'s parsing phase).

## 8. Future Considerations & CPG Enhancements

*   **Dynamic Sampling:** `Context.enabled?()` could become more sophisticated, consulting a dynamic sampling configuration (managed by `elixir_scope_config` or an AI component) rather than being a simple boolean.
*   **Event Prioritization:** The `RingBuffer` or `Ingestor` might implement logic to prioritize certain event types under high load, especially if CPG analysis indicates some events are more critical.
*   **Zero-Allocation Reporting:** For extremely hot paths, explore techniques to report events without allocating new event structs for every call, perhaps by pre-allocating or using a more raw binary protocol with the ring buffer.
*   **Direct to CPG-Aware Storage:** In a highly advanced scenario, if the `ast_node_id` is always present and reliable, some core events might be directly written to a CPG-aware indexing structure by the `Ingestor` to bypass some later correlation steps, but this adds complexity here.

## 9. Testing Strategy

*   **`ElixirScope.Capture.Context` Tests:**
    *   Verify correct initialization and clearing of process context.
    *   Test `enabled?()` under different scenarios.
    *   Test `current_correlation_id()`, `push_call_stack`, `pop_call_stack` for correct stack management.
    *   Test `with_instrumentation_disabled/1` ensures functions inside are not instrumented (mocking `enabled?` or checking no events are produced).
*   **`ElixirScope.Capture.RingBuffer` Tests:**
    *   Test `new/1` with valid and invalid options.
    *   Test `write/2` and `read/2`, `read_batch/3` for basic operation.
    *   Test buffer full scenarios with different `overflow_strategy` options, verifying correct behavior (dropping, blocking if implemented).
    *   Test concurrent writes and reads (if aiming for truly lock-free, this is complex but important).
    *   Test `stats/1`, `size/1`, `clear/1`, `destroy/1`.
    *   Performance benchmarks for write and read operations.
*   **`ElixirScope.Capture.Ingestor` Tests:**
    *   For each `ingest_*` function, verify it correctly constructs the appropriate `ElixirScope.Events.t()` struct and writes it to a mock/test `RingBuffer`.
    *   Test data truncation logic within the ingestors.
*   **`ElixirScope.Capture.InstrumentationRuntime` Tests:**
    *   For each `report_*` function:
        *   Test that it correctly calls the appropriate `Ingestor` function when `Context.enabled?()` is true.
        *   Test that it does nothing (or minimal work) when `Context.enabled?()` is false.
        *   Test correct management of `correlation_id` and call stack via `Context`.
*   **Performance Benchmarks:** Critical for `InstrumentationRuntime` calls and `RingBuffer.write` to ensure they meet sub-microsecond targets.
