# Algorithms and sources

CairnDom has no external runtime package dependencies. The implementation was
written for this project from algorithm definitions, with AI assistance.

- Cooper, Harvey and Kennedy, *A Simple, Fast Dominance Algorithm*, Rice TR-06-33870.
  Algorithm reference for reverse-postorder immediate dominators and frontiers.
  [Author paper archived at Tufts](https://www.cs.tufts.edu/~nr/cs257/archive/keith-cooper/dom06.pdf)
- Dominance, postdominance and SCC are established graph algorithms. Algorithm
  names and mathematical definitions are not claimed as new discoveries.
- Python's standard library is used for independent test oracles and file tests.
  No third-party graph implementation is copied or called by the runtime.
- Existing ecosystem work includes graph-library dominance in
  [moonbit-petgraph](https://github.com/V1GreenSummer/moonbit-petgraph) and IR-specific
  dominance and loops in [milkir](https://mooncakes.io/docs/Milky2018/milkir).
  These are overlap research references. Their source code is not vendored.

The repository's own source and examples use Apache-2.0. Synthetic example graphs
and generated test inputs contain no private application material.
