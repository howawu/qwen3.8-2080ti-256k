# Measurements and claim boundaries

All numbers are from one RTX 2080 Ti modified to 22 GB. Throughput depends strongly on prompt distribution and speculative acceptance rate.

| Scenario | Result | Interpretation |
|---|---:|---|
| Simple code generation, six cold prompts | 66.92 tok/s median; 56.35–74.98 range | The source of the “about 66 tok/s” headline |
| MATLAB Kalman workload | 44.87 tok/s | Reproduced real task after the Turing MMQ routing fix |
| Normal interactive use | about 45–48 tok/s | Operator-observed range, not a fixed benchmark |
| Repeated code request, warm n-gram table | 70.39 → 227.65 tok/s median | 3.23× on a deliberately repeated context; not representative of novel prose |
| Cross-request prefix reuse | 21.727 s → 0.356 s | 61× when 11,165 prompt tokens are reused and only 23 are new |
| Turing verifier routing | 35.72 → 44.87 tok/s | 25.63% from routing 7-wide speculative verification to MMQ |

## Why n-gram can be “almost free”

`ngram-mod` proposes tokens by looking up sequences already present in the prompt or earlier output. A hit avoids running a separate neural draft model for those proposed tokens; the target model still verifies them, so the work is not literally zero. It is especially effective for copied code, templates, logs, document rewrites and repeated conversation history. It gives little benefit on genuinely novel text.

The repeated-request figure is intentionally published as a feature demonstration. It must not be mixed with cold, independent-prompt benchmarks.

## Quality statements

- “Q4_K_M-like quality” is an operator assessment of this specific mixed Q2 recipe, not a perplexity-equivalence claim.
- “Less overthinking” comes from the EfficientThink/SimPO model behavior plus `reasoning-effort=low`; it is not attributed to KVMem or quantization alone.
- 256K is the logical context window. The GPU-resident target KV working set is 112,640 tokens; older context is retrieved through KVMem.
- Retrieval at long context is not mathematically identical to keeping all 256K KV positions resident.

Raw public summary: [`benchmarks/summary.json`](../benchmarks/summary.json).
