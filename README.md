# Tornado Cash Governance Lock

[![🕵️♂️ Test smart contracts](https://github.com/pcaversaccio/tornado-governance-lock/actions/workflows/test.yml/badge.svg)](https://github.com/pcaversaccio/tornado-governance-lock/actions/workflows/test.yml)
[![👮♂️ Sanity checks](https://github.com/pcaversaccio/tornado-governance-lock/actions/workflows/checks.yml/badge.svg)](https://github.com/pcaversaccio/tornado-governance-lock/actions/workflows/checks.yml)
[![License: WTFPL](https://img.shields.io/badge/License-WTFPL-blue.svg)](https://www.wtfpl.net/about/)

Permanently disables the Tornado Cash governance [`0x5efda50f22d34F262c29268506C5Fa42cB56A1Ce`](https://etherscan.io/address/0x5efda50f22d34F262c29268506C5Fa42cB56A1Ce) so that _no_ future governance proposal - malicious or otherwise - can ever be submitted, voted on, or executed again, while adding `unlockAll()` so previously locked TORN, including TORN locked specifically to vote this in, is never trapped.

## Mechanism

The governance proxy is a `TransparentUpgradeableProxy` whose admin is set to itself (`LoopbackProxy`), so a `delegatecall`ed proposal can act as its own admin. [`executeProposal()`](./src/FinalGovernanceLockProposal.sol) uses that path to:

- `upgradeTo(SealedGovernance)` - replaces the live implementation. `propose()`, `lock()`, `castVote()`, `execute()`, etc. cease to exist; only `lockedBalance()` and `unlockAll()` and survives.
- `changeAdmin(0x...dEaD)` - moves the proxy admin to an address with no known private key, closing the loopback itself so no future call can
  ever reach `upgradeTo()`/`changeAdmin()` again.

Both steps are checked on-chain, in the same transaction, before the proposal considers itself done:

- the EIP-1967 implementation slot is re-read and asserted equal to `SEALED_IMPLEMENTATION`,
- the EIP-1967 admin slot is re-read and asserted equal to the burn address,
- a canary call to the now-sealed proxy is asserted to revert with `SealedGovernance.TornadoCashGovernanceIsDead`.

Locked TORN itself lives in a separate vault contract ([`0x2F50508a8a3D323B91336FA3eA6ae50E55f32185`](https://etherscan.io/address/0x2F50508a8a3D323B91336FA3eA6ae50E55f32185)); `unlockAll()` calls `withdrawTorn(msg.sender, balance)` on it, matching how the live contract's own accounting is split between governance (bookkeeping) and the vault (custody).

## This Is Irreversible

Once executed, there is _no_ future proposal that can undo this (this is by design!). Get an independent security review, confirm the storage-layout assumption in `SealedGovernance` against the [live contract](https://etherscan.io/address/0x5efda50f22d34F262c29268506C5Fa42cB56A1Ce) yourself, and run the full `propose` -> `castVote` -> `execute` cycle on a mainnet fork (see the test [`testFinalGovernanceLockProposal`](./test/FinalGovernanceLockProposal.t.sol)).
