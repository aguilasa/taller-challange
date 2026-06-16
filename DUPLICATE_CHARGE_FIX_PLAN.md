# Duplicate Charge Fix Plan

## Problem Summary

Customers are being charged multiple times for the same purchase. The root cause is a
combination of failures across three layers: frontend UX, backend concurrency, and
storage. No single fix is sufficient — all layers must be addressed together.

---

## Vulnerability Map

```
User clicks button twice
        │
        ▼
[Frontend] newIdempotencyKey() called on each click
        │  → Two requests with DIFFERENT keys sent to backend
        │  → Backend deduplication never fires
        ▼
[Backend] ChargesService.createCharge()
        │  findByKey()  ←── non-atomic check
        │  processor.charge()  ←── 250ms gap, race window
        │  persist()  ←── write (no transaction, no lock)
        ▼
[Storage] ChargeStore (HashMap + ArrayList)
        │  → Not thread-safe
        │  → No unique constraint
        │  → Silent overwrite on duplicate key
```

---

## Issues

### Issue 1 — Frontend: New Idempotency Key on Every Submit

**File:** `frontend/src/App.jsx` — lines 4–6, 35

**Current code:**
```jsx
function newIdempotencyKey() {
  return `web_${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

// Called inside submitCharge on every click:
idempotencyKey: newIdempotencyKey()
```

**Problem:** Every button click generates a fresh key. This means double-clicking
"Create charge" sends two requests with completely different keys. The backend
idempotency guard receives two distinct keys and treats them as two independent
charges — which they are, from its perspective.

**Impact:** A user double-clicking or re-submitting due to a slow network creates
a guaranteed duplicate charge that no server-side check can prevent.

---

### Issue 2 — Frontend: No Loading State / Button Not Disabled

**File:** `frontend/src/App.jsx` — lines 26–41, 57

**Current code:**
```jsx
async function submitCharge(e) {
  e.preventDefault();
  setError('');
  // no isLoading = true here
  const charge = await createCharge({ ... });
  setLastCharge(charge);
  // no isLoading = false here
}

// Button is always enabled:
<button type="submit">Create charge</button>
```

**Problem:** The button remains clickable during the entire in-flight HTTP request
(which takes at least 250ms due to the artificial delay in `PaymentProcessor`).
There is also no error handling — if the request throws, the form resets silently
with no guard against re-submission.

**Impact:** Normal users, especially on slow connections, will naturally click
"Create charge" again thinking the first click didn't register.

---

### Issue 3 — Backend: Race Condition in Check-Then-Act

**File:** `backend/src/main/java/com/taller/charges/ChargesService.java` — lines 22–31

**Current code:**
```java
public Charge createCharge(ChargeRequest req) {
    Charge existing = store.findByKey(req.idempotencyKey());  // READ
    if (existing != null) {
        return existing;
    }
    // ← race window: another thread can pass the check here
    Charge charge = processor.charge(req, STRIPE_API_KEY);    // PROCESS (250ms)
    persist(req.idempotencyKey(), charge);                    // WRITE
    return charge;
}
```

**Problem:** Between the `findByKey` read and the `persist` write, a second
concurrent thread with the same idempotency key can pass the null check. Both
threads then call `processor.charge()` independently, creating two real charges.
The 250ms sleep in `PaymentProcessor` makes this window extremely easy to hit.

**Impact:** Even if the frontend sends the same idempotency key twice (e.g. from
a retry), both requests can race through and both charges succeed.

---

### Issue 4 — Backend: `@Transactional` Commented Out

**File:** `backend/src/main/java/com/taller/charges/ChargesService.java` — line 34

**Current code:**
```java
//    @Transactional
public void persist(String key, Charge charge) {
    store.save(key, charge);
}
```

**Problem:** The `@Transactional` annotation is intentionally commented out. Without
it, the check and the save are not part of an atomic unit. Even if a real database
were in place with a unique constraint on `idempotency_key`, the lack of a
transaction means the constraint violation would not roll back the already-processed
payment.

**Impact:** No atomicity between payment processing and state persistence. A charge
can be processed and then fail to persist, or be processed twice.

---

### Issue 5 — Storage: Non-Thread-Safe Collections

**File:** `backend/src/main/java/com/taller/charges/ChargeStore.java` — lines 15–27

**Current code:**
```java
private final Map<String, Charge> byKey = new HashMap<>();   // not thread-safe
private final Map<String, Charge> byId  = new HashMap<>();   // not thread-safe
private final List<Charge> all          = new ArrayList<>();  // not thread-safe

public void save(String key, Charge charge) {
    byKey.put(key, charge);   // can corrupt under concurrent writes
    byId.put(charge.id(), charge);
    all.add(charge);           // duplicate entries accumulate here
}
```

**Problem:** `HashMap` and `ArrayList` are not thread-safe. Under concurrent access:
- `HashMap` internal state can corrupt, causing data loss or exceptions.
- Two concurrent `save()` calls for the same key silently overwrite — the first
  charge is lost from `byKey` but both are in `all`, making them show up in
  `latest()` forever.
- `findByKey` can return stale/null even after a save completes (visibility
  problem without memory barriers).

**Impact:** The idempotency guard in `ChargesService` is unreliable even when
the logic is correct, because the underlying storage can return incorrect reads.

---

## Fix Plan

### Fix 1 — Generate Idempotency Key Once Per Form Fill

**File:** `frontend/src/App.jsx`

**Approach:** Move the idempotency key into component state. Generate it once when
the form mounts, and regenerate it only after a successful submission (so the user
can submit a new charge without refreshing). This ensures that any number of clicks
of "Create charge" for the same form state all carry the same key.

**Before:**
```jsx
function newIdempotencyKey() {
  return `web_${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

export function App() {
  const [form, setForm] = useState({ ... });
  // ...
  
  async function submitCharge(e) {
    e.preventDefault();
    const charge = await createCharge({
      ...form,
      amount: Number(form.amount),
      idempotencyKey: newIdempotencyKey()  // ← new key every click
    });
  }
}
```

**After:**
```jsx
function newIdempotencyKey() {
  return `web_${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

export function App() {
  const [form, setForm] = useState({ ... });
  const [idempotencyKey, setIdempotencyKey] = useState(newIdempotencyKey); // ← generated once
  // ...

  async function submitCharge(e) {
    e.preventDefault();
    const charge = await createCharge({
      ...form,
      amount: Number(form.amount),
      idempotencyKey  // ← same key for all retries of this form state
    });
    setIdempotencyKey(newIdempotencyKey());  // ← rotate only on success
  }
}
```

**Files changed:** `frontend/src/App.jsx`

---

### Fix 2 — Disable Submit Button During In-Flight Request

**File:** `frontend/src/App.jsx`

**Approach:** Add an `isLoading` boolean state. Set it to `true` before the async
call and back to `false` in a `finally` block. Pass it to the button as the
`disabled` prop. Also surface errors to the user so they understand why the button
was re-enabled without a successful charge.

**Before:**
```jsx
export function App() {
  const [error, setError] = useState('');

  async function submitCharge(e) {
    e.preventDefault();
    setError('');
    const charge = await createCharge({ ... });
    setLastCharge(charge);
  }

  return (
    // ...
    <button type="submit">Create charge</button>
  );
}
```

**After:**
```jsx
export function App() {
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(false);  // ← new

  async function submitCharge(e) {
    e.preventDefault();
    setError('');
    setIsLoading(true);  // ← lock button
    try {
      const charge = await createCharge({ ... });
      setLastCharge(charge);
      setIdempotencyKey(newIdempotencyKey());
    } catch (err) {
      setError(err.message);
    } finally {
      setIsLoading(false);  // ← always unlock, even on error
    }
  }

  return (
    // ...
    <button type="submit" disabled={isLoading}>
      {isLoading ? 'Processing...' : 'Create charge'}
    </button>
  );
}
```

**Files changed:** `frontend/src/App.jsx`

---

### Fix 3 — Make Idempotency Check Atomic in `ChargesService`

**File:** `backend/src/main/java/com/taller/charges/ChargesService.java`

**Approach:** Wrap the check-and-process logic in a `synchronized` block keyed on
the idempotency key. Use a `ConcurrentHashMap` of per-key locks (via
`computeIfAbsent`) to allow concurrent requests with *different* keys to proceed
in parallel while serializing requests with the *same* key.

This avoids a global lock (which would kill throughput) while still preventing
the race condition for any given key.

**Before:**
```java
public Charge createCharge(ChargeRequest req) {
    Charge existing = store.findByKey(req.idempotencyKey());
    if (existing != null) {
        return existing;
    }
    Charge charge = processor.charge(req, STRIPE_API_KEY);
    persist(req.idempotencyKey(), charge);
    audit.logCharge(charge, req.customerEmail(), req.cardToken());
    return charge;
}
```

**After:**
```java
// Per-key locks: concurrent requests with different keys run in parallel;
// same key is serialized to prevent double-charge race condition.
private final ConcurrentHashMap<String, Object> keyLocks = new ConcurrentHashMap<>();

public Charge createCharge(ChargeRequest req) {
    Object lock = keyLocks.computeIfAbsent(req.idempotencyKey(), k -> new Object());
    synchronized (lock) {
        Charge existing = store.findByKey(req.idempotencyKey());
        if (existing != null) {
            return existing;  // idempotent return
        }
        Charge charge = processor.charge(req, STRIPE_API_KEY);
        persist(req.idempotencyKey(), charge);
        audit.logCharge(charge, req.customerEmail(), req.cardToken());
        return charge;
    }
}
```

**Note on `@Transactional`:** The commented-out annotation is a no-op with the
current in-memory store. Restore it once a real database is wired up (see Fix 5).
Leave it commented for now to avoid a misleading compile warning.

**Files changed:** `backend/src/main/java/com/taller/charges/ChargesService.java`

---

### Fix 4 — Replace Non-Thread-Safe Collections in `ChargeStore`

**File:** `backend/src/main/java/com/taller/charges/ChargeStore.java`

**Approach:** Replace `HashMap` with `ConcurrentHashMap` and `ArrayList` with a
`CopyOnWriteArrayList`. The critical operation — checking for an existing key and
inserting if absent — must be done atomically via `putIfAbsent` on `byKey`. This
makes `findByKey`/`save` safe for concurrent access without an explicit lock.

The `putIfAbsent` return value also gives us a reliable signal: if it returns a
non-null value, a charge for that key was already saved concurrently and the
current one is a duplicate.

**Before:**
```java
private final Map<String, Charge> byKey = new HashMap<>();
private final Map<String, Charge> byId  = new HashMap<>();
private final List<Charge> all          = new ArrayList<>();

public void save(String key, Charge charge) {
    byKey.put(key, charge);
    byId.put(charge.id(), charge);
    all.add(charge);
}
```

**After:**
```java
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

private final ConcurrentHashMap<String, Charge> byKey = new ConcurrentHashMap<>();
private final ConcurrentHashMap<String, Charge> byId  = new ConcurrentHashMap<>();
private final CopyOnWriteArrayList<Charge> all        = new CopyOnWriteArrayList<>();

/**
 * Returns null if saved successfully, or the pre-existing charge if the key
 * was already present (concurrent duplicate detected).
 */
public Charge saveIfAbsent(String key, Charge charge) {
    Charge existing = byKey.putIfAbsent(key, charge);
    if (existing == null) {
        byId.put(charge.id(), charge);
        all.add(charge);
    }
    return existing;  // null = saved; non-null = duplicate blocked
}
```

Update `ChargesService` to use `saveIfAbsent` as a second line of defence:
```java
synchronized (lock) {
    Charge existing = store.findByKey(req.idempotencyKey());
    if (existing != null) return existing;

    Charge charge = processor.charge(req, STRIPE_API_KEY);

    Charge blocked = store.saveIfAbsent(req.idempotencyKey(), charge);
    if (blocked != null) return blocked;  // lost the race, return winner

    audit.logCharge(charge, req.customerEmail(), req.cardToken());
    return charge;
}
```

**Files changed:**
- `backend/src/main/java/com/taller/charges/ChargeStore.java`
- `backend/src/main/java/com/taller/charges/ChargesService.java`

---

### Fix 5 — Restore `@Transactional` and Add Database Persistence (Long-Term)

**Files:** `backend/pom.xml`, `ChargesService.java`, new entity/repository files

**Context:** The JPA dependency is currently commented out in `pom.xml`:
```xml
<!--
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-jpa</artifactId>
</dependency>
-->
```

**Approach:**
1. Uncomment the JPA dependency and add an embedded DB (H2 for dev, Postgres for prod).
2. Create a `@Entity` for `Charge` and a `@Repository` (Spring Data JPA).
3. Add a `UNIQUE` constraint on `idempotency_key` at the database level — this is
   the last line of defence against duplicates and the only guarantee that survives
   a process restart or horizontal scaling.
4. Restore `@Transactional` on `createCharge()` (not just `persist()`). The entire
   check-process-save sequence must be one transaction with `SERIALIZABLE` isolation
   or handled via a `SELECT ... FOR UPDATE` lock on the idempotency key row.

**Schema:**
```sql
CREATE TABLE charge (
    id               VARCHAR(32)    PRIMARY KEY,
    idempotency_key  VARCHAR(255)   NOT NULL UNIQUE,  -- ← the critical constraint
    amount           DECIMAL(10,2)  NOT NULL,
    currency         VARCHAR(3)     NOT NULL,
    customer_email   VARCHAR(255)   NOT NULL,
    card_token       VARCHAR(255)   NOT NULL,
    description      TEXT,
    status           VARCHAR(32)    NOT NULL,
    created_at       TIMESTAMP      NOT NULL
);
```

**Entity:**
```java
@Entity
@Table(name = "charge", uniqueConstraints = {
    @UniqueConstraint(columnNames = "idempotency_key")
})
public class ChargeEntity {
    @Id
    private String id;

    @Column(name = "idempotency_key", nullable = false, unique = true)
    private String idempotencyKey;

    // ... other fields
}
```

**Service with transaction:**
```java
@Transactional(isolation = Isolation.SERIALIZABLE)
public Charge createCharge(ChargeRequest req) {
    return chargeRepo.findByIdempotencyKey(req.idempotencyKey())
        .orElseGet(() -> {
            Charge charge = processor.charge(req, STRIPE_API_KEY);
            ChargeEntity saved = chargeRepo.save(toEntity(charge, req.idempotencyKey()));
            audit.logCharge(charge, req.customerEmail(), req.cardToken());
            return fromEntity(saved);
        });
}
```

**Files changed:**
- `backend/pom.xml`
- `backend/src/main/java/com/taller/charges/ChargesService.java`
- New: `ChargeEntity.java`, `ChargeRepository.java`
- New: `src/main/resources/application.properties` (datasource config)

---

## Implementation Order

Fixes must be applied in this order. Each stage is independently deployable and
makes the system safer than before even without the next stage.

```
Stage 1 — Frontend (no backend risk, deploy independently)
  ├── Fix 1: Idempotency key in state (same key per form fill)
  └── Fix 2: Disable button during submission + error handling

Stage 2 — Backend concurrency (in-memory store, no DB required)
  ├── Fix 3: Synchronized per-key lock in ChargesService
  └── Fix 4: ConcurrentHashMap + saveIfAbsent in ChargeStore

Stage 3 — Database persistence (requires infra change)
  └── Fix 5: JPA entity, unique DB constraint, @Transactional
```

**Why this order:**
- Stage 1 eliminates the most common real-world cause: user double-click. It also
  makes the backend idempotency key actually useful (right now each click sends a
  different key, so the backend check never fires).
- Stage 2 closes the server-side race condition for requests that do share a key
  (retries, concurrent API clients, load balancer retries).
- Stage 3 makes the guarantee durable across restarts and horizontal scaling.
  Without it, a server restart loses all in-memory state and all idempotency
  history — any retry after a restart would create a duplicate.

---

## Testing Checklist

### Stage 1 — Frontend
- [ ] Double-clicking "Create charge" fires only one HTTP request (check Network tab)
- [ ] Button shows "Processing..." and is disabled during the request
- [ ] Button re-enables after success; form is ready for a new charge with a new key
- [ ] Button re-enables after failure; same idempotency key is preserved for retry
- [ ] Submitting after a failed attempt retries with the same key (not a new one)

### Stage 2 — Backend
- [ ] Two concurrent requests with the same idempotency key return the same charge object
- [ ] Only one charge appears in `GET /charges` after the concurrent test above
- [ ] Concurrent requests with *different* keys both succeed independently
- [ ] No `ConcurrentModificationException` under load (run with JMeter or `ab`)

### Stage 3 — Database
- [ ] Restart the server; a repeated request with an old idempotency key returns the
      stored charge (not a new one)
- [ ] Database `charge` table has `UNIQUE` constraint on `idempotency_key`
- [ ] A manually injected duplicate (bypassing the service) is rejected by the DB
- [ ] `@Transactional` rollback works: if `audit.logCharge` throws, no charge is persisted

---

## Files Changed Summary

| File | Stage | Change |
|------|-------|--------|
| `frontend/src/App.jsx` | 1 | Idempotency key in state; `isLoading`; button disabled; error handling |
| `backend/.../ChargesService.java` | 2 | Per-key `synchronized` lock; `saveIfAbsent` usage |
| `backend/.../ChargeStore.java` | 2 | `ConcurrentHashMap`; `CopyOnWriteArrayList`; `saveIfAbsent` method |
| `backend/pom.xml` | 3 | Uncomment JPA + add H2/Postgres dependency |
| `backend/.../ChargesService.java` | 3 | `@Transactional(SERIALIZABLE)`; use JPA repository |
| `backend/.../ChargeEntity.java` | 3 | New JPA entity with `@UniqueConstraint` |
| `backend/.../ChargeRepository.java` | 3 | New Spring Data repository |
| `backend/src/main/resources/application.properties` | 3 | Datasource config |
