# AI-First Interview — Fullstack Engineer Java + React

## How to run this interview
Total time: 50 minutes.

### Pre-warm mandatory
Send the repo to the candidate before the interview. If they cannot get the setup working, that is already a relevant signal.

### Ground rules to read out loud
- “You must use AI tools. Cursor, Claude Code, Codex, Copilot — whatever you use day to day. Use it.”
- “Share your screen with the AI panel visible at all times. I want to see prompts and outputs, not just the code.”
- “Think out loud. The bug list I gave you is partial — find what you can.”
- “Submit fixes by editing files directly. Writing tests is optional but valued.”
- “There are pre-existing tests in the repo. They currently pass. They do not prove the app is correct.”

## What you are scoring
AI workflow is the primary signal. Bugs found are secondary. A candidate who finds 2 bugs but demonstrates clean prompt iteration and rigorous verification is stronger than one who finds 5 bugs by blindly accepting AI suggestions.

## What the interviewer should do
Stay mostly quiet. Brownfield is observation work.

Note timestamps for:
- First AI prompt
- First file opened
- First backend file opened
- First frontend file opened
- First bug found
- First AI hallucination caught
- First time they run backend/frontend/tests
- First new test or repro written

If they freeze for 5+ minutes, use one stress probe.

## Block 1 — Warm-up + AI probe, 5 min

### Q1 — Last AI use
“Tell me about the last time you used AI in real work. What were you solving, which tool did you pick, and why that one over the alternatives?”

### Q2 — AI was wrong
“Has AI ever given you an answer that looked right but was wrong? Walk me through how you caught it.”

### Stack-specific calibration probe, 60 sec
“What is one Java/Spring or React pattern where AI suggestions are subtly wrong, and how do you catch it?”

### Signal rubric
| Color | Pattern |
|---|---|
| Green | Names tools, articulates trade-offs, has at least one real story where AI was wrong and they verified it through test, repro, docs, logs, or code reading. |
| Yellow | Uses AI but cannot articulate criteria. Says “I use it for everything” but cannot recall a specific failure. |
| Red | “I don’t really use AI”, or “I trust it” with no verification story. |

Auditor note: If the Q1 story sounds polished, follow up: “Show me the commit, prompt history, or artifact.” If they cannot ground it, downgrade.

## Block 2 — Fullstack brownfield bug hunt, 40 min

### Setup
Backend: `cd backend && mvn spring-boot:run`. Runs on `:8080`.
Frontend: `cd frontend && npm run dev`. Runs on `:5173`.
Tests: `mvn test` and `npm test`.

Confirm screen share + AI panel visible.

### Problem statement, read verbatim
“We have a small payments admin app. Customers are reporting two issues: (1) some are seeing duplicate charges for the same purchase, and (2) security flagged something in the charge flow and support search UI. There may be more. Find what you can in 40 minutes. Use AI freely.”

## Bug map — DO NOT show candidate

### Backend bugs

#### B1 — TOCTOU race in createCharge, HARD
Where: `ChargesService.createCharge`.
Root cause: `store.findByKey -> processor.charge -> persist` is not atomic. Two concurrent requests with the same idempotency key can both charge.
Strong fix: per-key lock, `ConcurrentHashMap.computeIfAbsent` with lock cleanup, database unique constraint, or idempotency handled by processor/external store. Candidate discusses distributed lock/unique index for multi-instance production.
Weak fix: only checks twice without synchronization, or relies on frontend disabling the button.

#### B2 — Hardcoded Stripe-style key, EASY
Where: `ChargesService.STRIPE_API_KEY`.
Strong fix: environment/config binding, secrets manager/Vault, no secret committed to repo, rotation plan.

#### B3 — `@Transactional` self-invocation, HARD Spring trap
Where: `ChargesService.persist()` is annotated but called internally from the same bean.
Root cause: Spring proxy is bypassed; transaction does not actually apply.
Strong fix: transaction on public entry method, separate persistence service bean, or well-explained proxy-based design.
Weak fix: leaves annotation and assumes it works.

#### B4 — Plain `HashMap` and `ArrayList`, HARD
Where: `ChargeStore`.
Root cause: mutable in-memory store is not thread-safe under concurrent access.
Strong fix: `ConcurrentHashMap`, safe list strategy, or external DB. Candidate explains memory-vs-correctness trade-offs.

#### B5 — Audit log leaks card token, EASY-MEDIUM
Where: `AuditLog.logCharge`.
Strong fix: redact token, log last 4 only if appropriate, discuss PCI/log retention.

#### B6 — Wrong status code on idempotent retry, MEDIUM
Where: `ChargesController.createCharge` always returns 201.
Strong fix: 201 only for first creation; 200 or 409/semantic response for replay depending on chosen idempotency contract.

#### B7 — No amount/currency/email validation, EASY-MEDIUM
Where: `ChargeRequest` and controller.
Strong fix: Bean Validation annotations, `@Valid`, clear 400/422 behavior.

#### B8 — Latent SQL injection, BONUS
Where: `ChargeStore.findByEmail` builds a SQL string through concatenation.
Strong fix: parameterized query; recognizes in-memory demo still documents production behavior.

### Frontend bugs

#### F1 — Duplicate charge via unstable idempotency key, HARD
Where: `App.jsx`, `newIdempotencyKey()` is called on every submit.
Root cause: repeated clicks/network retry generate different keys, defeating backend idempotency.
Strong fix: stable idempotency key per checkout attempt, disabled pending state, retry-safe request handling.
Weak fix: only disables button but keeps unstable key.

#### F2 — No pending/error control around submit, MEDIUM
Where: `submitCharge`.
Root cause: double click can fire multiple requests; errors are not handled with `try/catch`.
Strong fix: `isSubmitting` guard, idempotency key stable, `try/catch/finally`, user feedback.

#### F3 — Card token leaked to console and localStorage, EASY-MEDIUM
Where: `console.log` in `submitCharge`; `localStorage.setItem('lastCardToken', ...)` in `useEffect`.
Strong fix: remove logging/storage, never persist sensitive tokens client-side, explain PCI/security implications.

#### F4 — XSS through `dangerouslySetInnerHTML`, HARD React/security trap
Where: support message rendering.
Root cause: backend returns HTML built from user-controlled customer name/email; frontend injects it directly.
Strong fix: render as text, sanitize with a vetted sanitizer if HTML is truly required, prefer server-safe templates and strict content contract.
Weak fix: manually strips `<script>` only.

#### F5 — Unencoded query param in support search, MEDIUM
Where: `api.js`, `searchByEmail(email)`.
Root cause: string interpolation without `encodeURIComponent`; malformed query/injection/confusing server behavior.
Strong fix: `URLSearchParams` or `encodeURIComponent`; backend still validates/parameterizes.

#### F6 — Index used as React key, LOW-MEDIUM
Where: `results.map((charge, index) => <li key={index}>...)`.
Root cause: stale UI/render bugs when list order changes.
Strong fix: stable key such as `charge.id`.

## Stress probes
Use sparingly.

At ~12 min:
“Two users double-click the Create Charge button, or the browser retries after a timeout. Walk me through what happens across React, HTTP, Spring, and the store.”

At ~22 min:
“What would still be broken if the frontend disables the button but the backend receives two identical requests 5 ms apart?”

At ~30 min:
“If AI suggests adding `@Transactional` to `persist()` or wrapping the React HTML in a sanitizer regex, what would you challenge?”

At ~35 min:
“In production with multiple backend instances behind a load balancer, which of your fixes still holds?”

## AI workflow rubric, 60% weight
Rate 1–4.

| Dimension | 1 Poor | 2 Mixed | 3 Strong | 4 Exceptional |
|---|---|---|---|---|
| Orientation | Reads randomly; no AI mapping. | Asks for a tour but does not use it. | Uses AI to map backend + frontend, then targets suspicious flows. | Creates repo context/rules, asks AI to build a threat/concurrency map, validates manually. |
| Prompt quality | One-liners. | Some context, no constraints. | Structured prompts with scope, constraints, and expected evidence. | Iterative prompts; asks for hypotheses, repros, tests, and counterexamples. |
| Verification | Accepts AI/code without running. | Runs once at the end. | Reproduces each bug or explains evidence before fixing. | Writes failing test/repro before fixing at least one backend or frontend bug. |
| Hallucination catch | Does not notice. | Catches syntax-level mistakes. | Catches at least one wrong API/package/security/concurrency suggestion. | Anticipates likely AI mistakes and prevents them through constraints. |
| Control | AI drags them. | Mixed. | Directs AI and knows next steps. | Treats AI as a junior pair; rejects suggestions with technical rationale. |

## Technical rubric, 40% weight
Rate 1–4.

| Dimension | 1 Poor | 2 Mixed | 3 Strong | 4 Exceptional |
|---|---|---|---|---|
| Bugs found | 0–2 mostly obvious. | 3 bugs, mostly easy. | 4–5 bugs including one hard fullstack/concurrency/security issue. | 6+ bugs including backend race and frontend idempotency/XSS. |
| Fix quality | Plasters symptoms. | Fixes surface issues. | Fixes root cause and explains why. | Root cause + regression test/repro + production caveat. |
| Fullstack reasoning | Treats frontend/backend separately. | Finds issues in both but no flow reasoning. | Explains end-to-end charge flow and failure modes. | Connects UX retry, HTTP semantics, idempotency, backend atomicity, logging, and production topology. |
| Prioritization | Random order. | Some priority. | Security and duplicate charges first. | Explicit triage: customer impact, security, data consistency, test strategy. |
| Test skepticism | Green tests = fine. | Notices partial tests. | Identifies missing concurrency/security paths. | Writes new failing test/repro for duplicate charge, XSS, or validation. |
| Communication | Silent. | Explains after. | Narrates while working. | Negotiates trade-offs, pushes back, owns design decisions. |

## Decision heuristic
Strong yes-hire:
- AI workflow average >= 3
- No 1s in Verification, Hallucination catch, or Control
- Finds at least 4 bugs including either B1 or F1 and at least one security issue
- Explains root cause for 2+ issues
- Writes or clearly designs one failing test/repro

Lean hire:
- AI workflow average >= 3
- Finds 3+ meaningful bugs across backend and frontend
- No critical weakness in verification/control

No hire:
- Any 1 in Verification, Hallucination catch, or Control
- Blindly accepts AI suggestions
- Only finds UI/cosmetic issues and misses duplicate charge or security themes
- Cannot explain why passing tests are insufficient
