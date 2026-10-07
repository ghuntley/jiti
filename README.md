# Jiti

**Grow a running Lisp application by talking to it.**

Licensed under the [MIT License](LICENSE).

Jiti is a cooperative kernel for developing and using a live Common Lisp application through chat. Ask for a function, try it against the application's data, then ask for another capability that builds on it. Accepted definitions remain available to later requests and can be recovered in a fresh process.

Application behaviour comes from the Lisp you add and the resources your world adapter supports. You can start with an empty function catalogue or extend an existing application. The same interface lets you inspect definitions, execute expressions, preview changes, and repair a paused call.

An illustrative conversation:

```text
chat> Add uppercase-string. Return an uppercased copy of the input.
chat> Add reverse-string. Return a reversed copy without modifying the input.
chat> Uppercase "Hello", then reverse the result using those functions.
chat> Save that combination as shout-backwards.
chat> /describe shout-backwards
chat> /execute (shout-backwards "Hello")
```

The resulting composition is ordinary Lisp:

```lisp
(defun shout-backwards (text)
  (reverse-string (uppercase-string text)))
```

Each accepted function joins an inspectable catalogue with its arguments, documentation and source. Once defined, it runs as Lisp; calling it does not inherently require model inference.

Install [Nix and devenv](https://devenv.sh/getting-started/), then start the terminal application:

```sh
git clone https://github.com/ghuntley/jiti.git
cd jiti
devenv shell -- image-repl
```

The development environment supplies SBCL, Lisp libraries, Python and the terminal dependencies. The default application has a managed `*state*` table containing `:x`, initially zero, and a `counter` function. Its workspace is `.image-agent/workspaces/demo/`. Reopening the same workspace recovers accepted code and data.

For chat, configure a model and either a credential file or `OPENAI_API_KEY`:

```sh
export OPENAI_MODEL='your-model-id'
export OPENAI_API_KEY_FILE='/absolute/path/to/api-key'
devenv shell -- image-repl
```

`OPENAI_BASE_URL` optionally selects a service implementing the Responses API; the default is `https://api.openai.com/v1`. The launcher also discovers local Underclass configuration. Explicit environment settings take precedence, and `--model NAME` overrides model selection. Credentials are excluded from diagnostic records and failure artifacts.

Manual Lisp works without model credentials. Try this in a separate workspace:

```sh
devenv shell -- image-repl --store .image-agent/workspaces/manual/
```

```text
chat> /develop (defun twice (x) "Double X." (* x 2))
chat> /execute (twice (twice 3))
chat> /preview (incf (gethash :x *state*))
chat> /execute (counter)
chat> /functions
chat> /history
chat> /quit
```

The nested call returns `12`. Preview returns `1` while restoring the counter to `0`. Reopen the same workspace to call `twice` again. This exercises definition, composition, managed preview and recovery entirely locally.

The model connects to Lisp through a tool loop:

```mermaid
flowchart LR
    U[Your request] --> M[Model service]
    M -->|Tool call| C[Controller]
    C -->|Validated action| W[Persistent SBCL worker]
    W -->|Values, checks, or a live pause| C
    C -->|Actual result| M
    W --- A[Application functions and managed data]
```

The controller supplies instructions, registered tool descriptions, conversation context and current worker observations. The model can inspect available functions, read source, request development, or execute an expression. Complete tool calls are validated and routed one at a time. The next model request receives the actual outcome.

`develop_form` adds, redefines or removes functionality; `execute_form` uses existing functionality. Both share one evaluator and transaction engine. Other tools expose caller checks, operations, revision history, rollback, restart resumption and attempt abortion. Observation generations guard against stale actions; revision IDs identify saved application states.

One persistent worker thread owns live evaluation for each managed world. The controller exchanges actions and observations with it through mailboxes. This ownership preserves the active stack across prompts, including the dynamic extent of a paused restart. [The kernel diagram](launch/kernel-diagrams/02-kernel-ownership.svg) shows these boundaries.

A world adapter tells the kernel what it manages. It supplies the evaluation package, observations, function catalogue, checkpoints and restoration, a deterministic managed-state representation, and export/import hooks for persistence. The reference adapter covers direct named `defun` definitions, supported function removals, and readable data in a state table. Additional resources require adapter hooks that cover their effects and recovery.

Every development or execution attempt takes a checkpoint before reading, compilation and evaluation. Ordinary execution retains successful safe managed changes. An explicit preview returns bounded printable results and restores the checkpoint. The caller supplies two distinct kinds of executable checks:

| Check | Meaning | Effect |
| --- | --- | --- |
| Goals | Has the requested capability been achieved? | Unmet goals allow safe intermediate progress. |
| Safety invariants | Is this candidate managed state acceptable? | Failed or signalled checks reject the attempt and restore its checkpoint. |

These checks belong to the caller. Model-generated implementation or a completion message cannot replace the acceptance contract. Interactive sessions remain available after goals pass; autonomous evolution requires executable goals.

When application code signals an error, the worker can report the condition and available restarts while retaining the original call. The controller can request repair forms on that same worker, then invoke an offered restart within its live dynamic extent. The available continuation paths depend on the running program's restarts.

Redefining a function preserves existing frames' bodies. Subsequent calls through non-inline global function names can reach updated definitions. The [scripted repair demonstration](launch/kernel-diagrams/03-paused-function-repair.svg) shows an original invocation returning through its version-one frame and the following invocation entering version two. The outer evaluation and its repairs share one provisional checkpoint; abort unwinds the attempt before restoration.

There are three separate lifetimes to keep track of:

| State | Lifetime |
| --- | --- |
| Conversation context | Session memory; can be compacted or cleared independently of the worker. |
| Application execution | The live worker, including paused frames and restart identities. |
| Accepted managed code and data | Durable revisions that can be imported into a fresh process. |

Every attempt gets an operation identity and diagnostic record. Accepted changes create revisions; pure calls, identical definitions and final-state no-ops do not. The store publishes immutable revision artifacts and updates an atomic `CURRENT` pointer. Recovery imports accepted state, marks unfinished operations interrupted, and never replays them. Rollback publishes an earlier managed state as another revision, retaining the intervening history. Revisions currently require the same SBCL version.

The terminal supports multiline input, editing, syntax highlighting and live restart panels. Enter submits complete input; Alt+Enter inserts a newline. Ctrl+C clears the input draft; `/abort` unwinds a paused attempt. `--plain` selects the line interface, which is also used for pipes. Submitted input is stored in the workspace's `input-history.txt` with permissions `0600`; model replies and conversation context remain session-only.

| Command | Purpose |
| --- | --- |
| `/functions [OFFSET]`, `/describe NAME` | Browse the catalogue and inspect source. |
| `/develop FORM`, `/execute FORM` | Change functionality or run an expression. |
| `/preview FORM` | Return values and restore managed effects. |
| `/status`, `/operations`, `/history` | Inspect the worker, recent attempts and accepted revisions. |
| `/rollback ID\|NUMBER\|previous` | Restore an earlier state as a new revision. |
| `/abort` | Unwind a paused attempt and restore its checkpoint. |
| `/context`, `/compact`, `/context clear` | Inspect, compact or clear conversation memory. |
| `/model [NAME]` | Inspect or switch the model; switching clears conversation context. |
| `/mode chat\|lisp`, `/chat TEXT` | Switch input mode or send a prompt from either mode. |
| `/help`, `/quit` | Show all commands or close the worker. |

Chat defaults to 20 tool calls per prompt and a 1,000-action worker budget. `--tool-limit`, `--budget`, `--context-tokens` and `--compact-threshold` configure these bounds. Conversation compaction preserves the worker and any live pause. Fresh observations and tool results take precedence over summaries. Use `devenv shell -- image-repl --help` for startup options.

To load your own application, create a Lisp file defining `CL-USER:MAKE-CLI-WORLD`:

```lisp
(in-package :cl-user)

(defun make-cli-world ()
  (let* ((world (image-agent:make-reference-world :initial '((:x . 0))))
         (table (image-agent:reference-table world)))
    (list :id "my-app"
          :world world
          :invariants
          (list (cons :nonnegative
                      (lambda ()
                        (let ((x (gethash :x table)))
                          (and (integerp x) (>= x 0)))))))))
```

```sh
devenv shell -- image-repl --program app.lisp --store .image-agent/workspaces/my-app/
```

The adapter ID must be stable and contain letters, digits, hyphens or underscores. Workspaces check adapter identity and permit one CLI process at a time. Add caller-owned `:goals` when you want executable completion criteria. [The expense example](examples/expense-tracker.lisp) demonstrates fixture-based goals and safety invariants starting with no application functions.

For embedding, load the ASDF systems in [image-agent.asd](image-agent.asd). `image-agent` contains the core kernel and property checks; `image-agent/store` adds persistence and the reference world; `image-agent/openai` adds the Responses proposer; `image-agent/cli` adds tools and chat. `make-session`, `session-step` and `close-session` expose the worker protocol, while `run` drives it with an injected proposer. See [kernel.lisp](src/kernel.lisp), [reference-world.lisp](src/reference-world.lisp) and the [architectural decisions](docs/adr/) for the contracts.

Verify the implementation locally:

```sh
devenv shell test
devenv test
devenv shell test-stress
devenv shell test-replay /tmp/image-agent-counterexample-424242.sexp
```

`test` runs the deterministic offline Lisp suite. `devenv test` also runs ADR, CLI and terminal checks. Property failures retain replayable minimized traces. `devenv shell test-live` uses configured model credentials to verify real tool use, composition and fresh recovery. `devenv shell -- experiment-reverse` runs a bounded Unicode grapheme-reversal experiment with caller-owned fixed and generated checks, recovery, rollback and offline counterexample replay; see [experiments.lisp](src/experiments.lisp).

Jiti assumes cooperative Lisp code. Managed checkpoints cover the adapter's declared resources; external I/O, background threads and arbitrary resource effects need appropriate integration. Package locks and form validation protect against mistakes, while crash, hang and hostile-code isolation require an external process boundary. Active frames, cached function objects and inline sites can retain earlier definitions. These boundaries are part of the kernel's design, alongside live worker ownership and durable managed state.
