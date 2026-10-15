# BloxIMD tests

The existing `BloxIMD.t.sol` suite remains unchanged. It covers the requested name,
symbol, decimals, constructor mint, immediate deployer allocation, basic ERC-20
behavior, launch-style distribution, and rejection of administrative entry points.

`BloxIMDProperties.t.sol` adds boundary and failure-path tests for:

- One base unit, the whole supply, `uint256.max`, and finite `uint256.max - 1`
  allowances.
- Replayed spending after exhaustion, revocation of unlimited allowances, and
  replacement of revoked approvals.
- Direct and delegated self-transfers, including allowance consumption and
  insufficient balance.
- Isolation between owners and spenders, repeated approval idempotence, and
  atomic rollback when balance or allowance is insufficient.
- Zero-address rejection, arbitrary nonzero recipients, and contract recipients
  with no token receiver hook.

Its eight fuzz properties each run 1,000 cases. Inputs are bounded without
discarding cases; unrestricted approval values cover the full `uint256` domain.

`BloxIMDInvariant.t.sol` runs three invariants after every random handler action:

1. Supply stays at `10^27` base units and equals the sum of all reachable balances.
2. Each actor's balance matches its authorized transfers.
3. Every owner/spender allowance matches approvals, revocations and spending.

The handler deploys the real token and divides its supply among four actors,
including the immediate deployer. Transfers stay within this closed population,
making the balance sum exhaustive. Ghost balances and allowances are initialized
from the specification and updated from actions, never copied from token getters.
Checking each account separately detects theft that a supply-only check misses.

Eight actions mix transfers, approvals and delegated spending with deliberate
over-balance, over-allowance, zero-recipient and zero-spender failures. Approvals
include revocations, unlimited amounts and large finite amounts. Delegated
spending uses existing approvals, allowing histories to include replacement and
exhaustion. Expected failures are caught and checked for their exact error data;
unexpected handler reverts fail the campaign. Invariants also verify that failed
calls leave the complete ledger unchanged.

Inline settings select 256 sequences of depth 128 and `fail-on-revert = true`.
After each sequence, all holders must be able to transfer their entire balances,
and metadata must still match the task. A deterministic handler replay pins
edge cases, exercises every action, and confirms that both direct and delegated
transfers actually move value.

The support files declare only the native Foundry cheatcode and invariant
targeting interfaces used here. No additional package, network, fork, environment
mutation, storage mutation or private key is needed. Actor addresses are local
test fixtures. The existing simulated distribution test checks token accounting;
the separate supplied launch harness owns actual pool deployment and swap checks.

Run from the repository root with the existing compiler available:

```sh
forge build --offline
FOUNDRY_FUZZ_SEED=0x1975e6365e0e4acefff1e52cb9f7cb3f4af935c49bbf482b72be56a483370031 forge test --offline
```

During this test-only assignment, add `--out test/scratch/out --cache-path
test/scratch/cache` to each command to keep generated artifacts inside scratch.
Delivered tests do not import or depend on anything under `test/scratch/`.
