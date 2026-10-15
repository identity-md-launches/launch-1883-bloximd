# BloxIMD (BLOX)

A fixed-supply ERC-20 for Ethereum, implemented in `src/BloxIMD.sol` with
OpenZeppelin Contracts v5.1.0.

| Parameter | Value |
| --- | --- |
| Solidity contract | `BloxIMD` |
| Token name | `BloxIMD` |
| Symbol | `BLOX` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Base-unit total supply | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None |
| Initial recipient | Immediate deployer (`msg.sender`) |

The constructor mints the entire supply once and emits
`Transfer(address(0), deployer, 10^27)`. There are no further allocations or
constructor interactions with other contracts.

## Behavior and assumptions

The requested token is interpreted as a standard ERC-20. Transfers deliver the
exact amount specified; there are no fees, taxes, rebases, transfer limits or
external callbacks. Successful `transfer`, `approve` and `transferFrom` return
`true`; invalid operations revert with OpenZeppelin's ERC-6093 custom errors.
Zero-value transfers to valid recipients and self-transfers are supported.
Transfers to the zero address and approvals to a zero spender revert.

Approvals replace the existing allowance. Finite allowances decrease when spent;
an allowance of `type(uint256).max` retains OpenZeppelin's unlimited-allowance
semantics. `approve` emits `Approval`; spending an allowance does not emit an
additional `Approval` event. Transfers, including zero-value transfers, emit
`Transfer`.

There is no owner, administrator, pause, blacklist, confiscation, public mint,
burn, upgrade or initialization function. Supply remains fixed for the lifetime
of this deployed contract. The deployer has the same token rights as other
holders after construction. Holders authorize spending through allowances.

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x1975e6365e0e4acefff1e52cb9f7cb3f4af935c49bbf482b72be56a483370031 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, Cancun EVM, optimization with 200 runs and
`bytecode_hash = "none"`. The complete imported OpenZeppelin source subset and
its MIT license are ordinary files in `lib/openzeppelin-contracts/`; no
dependency installation, submodules, network, FFI, filesystem permissions or
environment configuration are needed by the contracts or tests. Foundry must
have the pinned compiler available for offline execution. The tests declare the
small cheatcode interface they use and require no test library.

The suite checks metadata, mint events, direct and factory deployment, exact
transfers and events, zero and self-transfers, finite and unlimited approvals,
replacement and revocation, delegated spending, launch-style distribution and
claims, rejected invalid operations, atomic failure, and absence of privileged
entry points. Four fuzz tests exercise transfer round trips, delegated spending,
over-balance rejection and 32-step transfer sequences with conservation checks
after every step. Each runs 1,000 cases by default.

The local distribution test checks token accounting with simulated actors; it
does not deploy a Uniswap pool or execute the separate environment-dependent
protected launch harness.

## Deployment and operational responsibilities

Deploy the creation bytecode for `src/BloxIMD.sol:BloxIMD` directly with no
constructor arguments and no ETH value. Do not use a proxy. No application
contracts, linked libraries, initialization calls, owner address, external
service settings or post-launch configuration are required.

In the custom-token launch, the deploying factory is `msg.sender` and receives
all `10^27` base units. The external launch system is responsible for distributing
the supply, including its swarm allocation, liquidity funding and remainder.
The token constructor does not perform these transfers. A direct wallet
deployment instead allocates the entire supply to that wallet.

The launch operator must select the intended Ethereum deployment flow, review
the compiled artifact and constructor arguments, verify the deployed source and
check name, symbol, decimals, total supply and initial recipient. Deployment,
pool creation, signing and broadcasting are outside this source deliverable.
The separate launch process supplies its own manifest.

After launch there is no privileged maintenance role or recovery mechanism.
Holders are responsible for recipient addresses and allowance management. Use
bounded approvals and revoke unused allowances. To change an existing nonzero
allowance, first revoke it in a confirmed transaction before granting the new
amount to reduce the ERC-20 approval race risk. Tokens sent to an inaccessible
address or to this token contract cannot be recovered by an administrator.

## Security review

The implementation adds only the fixed supply constant and a constructor mint
to the vendored ERC-20. Review against the supplied security reference found no
external calls, oracle/randomness dependencies, privileged operations, proxies
or upgrade paths. Arithmetic and balance/allowance validation are provided by
OpenZeppelin's ERC-20. Reentrancy guards are unnecessary because token operations
make no external calls. Zero addresses are rejected where required while ERC-20
zero-value transfers remain valid.

Local validation uses Foundry build, unit tests and seeded fuzz tests. Slither
and Mythril were not run. These checks do not constitute an independent security
audit; production release review remains the launch operator's responsibility.
