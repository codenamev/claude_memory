# **Organizational Memory: Axioms, Formulae, and Scale Playbook**

*A north star for building, evaluating, or reasoning about org-memory systems.*

---

## I. Core Premise

> **When implementation becomes cheap, meaning becomes the bottleneck.**

Modern teams no longer fail because they cannot build fast enough.
They fail because they cannot **remember why they built what they built**.

Organizational memory is not storage.
It is the system that preserves **decision-quality over time**.

---

## II. Foundational Axioms

### **Axiom 1: Code is no longer the primary artifact**

The primary artifact is the **decision**.

Code is a consequence of decisions.
Tests, reviews, and conversations encode intent more faithfully than the final diff.

---

### **Axiom 2: Truth is temporal**

There is no permanent truth.

Only:

> *What was believed to be true, by whom, at a given time.*

Any system that cannot answer *“when was this true?”* will hallucinate certainty.

---

### **Axiom 3: Memory without resolution becomes noise**

Captured information increases entropy unless conflicts are resolved.

Storing more ≠ knowing more.

Resolution creates signal.

---

### **Axiom 4: Provenance outweighs content**

A weak fact with strong provenance is more valuable than a strong claim with no source.

Who said it, when, and with what authority matters more than phrasing.

---

### **Axiom 5: Meaning must be captured at the moment of action**

Reconstruction after the fact is lossy.

If memory is not embedded in the execution path, it decays immediately.

---

## III. Primitive Building Blocks

### **1. Fact (Temporal)**

```
(subject, predicate, object,
 valid_from, valid_to,
 source, confidence)
```

Facts are intervals, not fields.

---

### **2. Decision**

```
(action,
 context,
 alternatives,
 rationale,
 approver,
 time,
 outcome)
```

If “because” cannot be answered, the decision is incomplete.

---

### **3. Trace (Because Graph)**

Edges matter more than nodes.

* evidence → rationale
* rationale → decision
* decision → action
* policy(version) → constraint
* approver → authorization

No edges = folklore.

---

### **4. Status**

Every belief must be one of:

* current
* superseded
* disputed

If none apply, the system is lying.

---

## IV. Core Formulae

### **1. Organizational Memory Value**

Let:

* **R** = rework avoided
* **O** = onboarding acceleration
* **D** = decision-quality improvement
* **A** = adoption rate (0–1)
* **C** = system cost
* **P** = risk cost (privacy, error, misuse)

[
\text{Memory Value} =
A \cdot (R + O + \lambda D) - (C + P)
]

If adoption is near zero, value is near zero regardless of intelligence.

---

### **2. Temporal Truth Resolution**

At time **t**:

[
Truth(t) =
\arg\max_{claims}
(confidence \times authority(source))
]

subject to:

[
valid_from \le t < valid_to
]

Truth is **time-sliced and source-weighted**.

---

### **3. Signal-to-Entropy Ratio**

[
SER = \frac{\text{Resolved Decisions}}{\text{Captured Artifacts}}
]

Healthy systems increase SER over time.

Wikis decay. Memory systems must sharpen.

---

## V. Scale Playbook

### **Scale 1: Individual or Tiny Team (1–5)**

**Goal:** Stop losing important decisions.

**Characteristics**

* Low conflict
* High context sharing
* Minimal governance

**Do**

* Capture PRs, LLM sessions, key discussions
* Distill into:

  * Decision
  * Learning
  * Open Question
* Append-only with timestamps

**Avoid**

* Complex ontologies
* Automatic resolution
* Over-structuring

**Failure Mode**

* Memory becomes a diary, not a tool

---

### **Scale 2: Team / Org (5–50)**

**Goal:** Prevent contradictions from compounding.

**Add**

* Supersedes links
* Decision status (current / superseded / disputed)
* Authority weighting
* Policy versioning

**Key Question**

> “Which belief is currently in force?”

**Failure Mode**

* Two truths exist and no one knows which one applies

---

### **Scale 3: Organization / Enterprise (50+)**

**Goal:** Make memory unavoidable.

**Add**

* Event logs of actions
* Mandatory capture points
* Approval instrumentation
* Audit-friendly traces

**Rule**

> If it materially affects the business, it must be captured at execution time.

**Failure Mode**

* Post-hoc archaeology
* Compliance theater
* Memory drift between teams

---

## VI. What This System Delivers

| Recipient    | Value                              |
| ------------ | ---------------------------------- |
| Engineers    | Less rework, faster onboarding     |
| Product      | Clear rationale, fewer regressions |
| Leadership   | Decision continuity                |
| AI agents    | Grounded reasoning                 |
| Organization | Institutional durability           |

---

## VII. The North Star Question

Every org-memory system must answer, clearly and reliably:

> **“Why are we the way we are right now?”**

If it cannot answer that question:

* confidently
* temporally
* with provenance

…it is not memory.
It is storage wearing a lab coat.

---

## VIII. Final Reduction

If all of this collapses into one sentence:

> **Organizational memory exists to preserve decision-quality across time, scale, and personnel change.**

Everything else is implementation detail.
