# FlowSwap

A fork of the [Uniswap v3](https://github.com/Uniswap/v3-core) contracts, used as a
[Foundry](https://book.getfoundry.sh/) **research / experimentation sandbox** — fee tiers,
LP returns, arbitrage/MEV simulations, and similar.

> ⚠️ **Testnet / local only — no real funds, ever.** This is not a product. It is not affiliated
> with, endorsed by, or connected to Uniswap Labs. The Uniswap name and logo are trademarks of
> Uniswap Labs and are **not** used here. The underlying v3 contracts are GPL-licensed.

The v3-core and v3-periphery contracts are vendored as editable source under `src/core/` and
`src/periphery/`; external dependencies (OpenZeppelin, Uniswap solidity-lib, base64) are pulled
in as git submodules under `lib/`.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)
- The contracts compile with **Solc 0.7.6**. On Apple Silicon (arm64) Macs this needs
  **Rosetta 2** (`softwareupdate --install-rosetta --agree-to-license`), since solc 0.7.6 ships
  as an Intel-only binary.

## Getting started

The dependencies in `lib/` are git submodules, so clone **with `--recurse-submodules`**:

```shell
git clone --recurse-submodules https://github.com/anchitjaincfa/flowswap.git
cd flowswap
```

Already cloned without it? Fetch the submodules before building:

```shell
git submodule update --init --recursive
```

> If `lib/` looks empty or `forge build` complains about missing files, you almost certainly
> skipped the submodule step above.

## Build & test

```shell
forge build      # compiles all contracts (Solc 0.7.6)
forge test       # runs the integration test (deploy factory/router/NPM, create pool, add liquidity, swap)
```

## Local deploy (Anvil)

Spin up a local chain and run the deploy script. This deploys the factory, a WETH9 mock, the
swap router, and the position manager; mints two mock faucet tokens (fTKA / fTKB); creates a
pool; and seeds 100k/100k liquidity.

In one terminal:

```shell
anvil
```

In another (the key below is Anvil's well-known, public default account #0 — local use only):

```shell
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  forge script script/DeployFlowSwap.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

## Configuration

Copy the env template and fill in your own values (the real `.env` is git-ignored and must never
be committed):

```shell
cp .env.example .env
```

`.env` holds RPC endpoints, an optional Arbiscan key, and a **dev-only** testnet deployer private
key. Public fallback RPCs are listed in `.env.example` if you don't have an Alchemy/Infura key.

## Status

Working: `forge build`, the integration test, and a full local Anvil deploy (pool + liquidity +
live swap). A public Arbitrum Sepolia deploy is set up but not yet broadcast (needs free testnet
ETH in the deployer wallet).
