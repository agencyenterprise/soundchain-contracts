# SoundChain Omnichain Contracts - HANDOFF

**Priority: HIGH - Complete Before Launch**
**Last Updated: December 20, 2025**
**Status: Architecture Complete, Pending Deployment**

---

## Executive Summary

The SoundChain omnichain infrastructure is now architecturally complete. This handoff documents everything needed to deploy and activate the 0.05% fee collection system across 23+ chains.

---

## What Was Built

### Smart Contracts (EVM - Solidity)

| Contract | Purpose | Status |
|----------|---------|--------|
| `OmnichainRouter.sol` | Grand Central Station - routes ALL cross-chain operations | Compiled |
| `ChainConnector.sol` | Lightweight relay per chain (spoke contracts) | Compiled |
| `TokenListingProxy.sol` | Multi-token NFT listings (32+ tokens) | Compiled |
| `BundleListingProxy.sol` | Bundle listings with 6 tiers | Compiled |
| `SweepProxy.sol` | Floor sweep, batch operations, airdrops | Compiled |
| `MultiTokenMarketplace.sol` | Marketplace with collaborator royalties | Compiled |
| `SCidRegistry.sol` | On-chain SCid registration | Compiled |
| `SoundchainFeeCollector.sol` | Fee collection and Gnosis Safe routing | Compiled |

### Smart Contracts (Solana - Rust/Anchor)

| Program | Purpose | Status |
|---------|---------|--------|
| `soundchain-scid` | SCid registry for Solana | Written |
| `soundchain-marketplace` | Multi-token marketplace for Solana | Written |

### Configuration Files

| File | Purpose |
|------|---------|
| `config/token-chain-mapping.json` | Complete token-chain mapping (24 tokens × 23 chains) |
| `Anchor.toml` | Solana program configuration |

### Deployment Scripts

| Script | Purpose |
|--------|---------|
| `scripts/deploy-omnichain-router.ts` | Deploy Grand Central Station |
| `scripts/deploy-chain-connector.ts` | Deploy per-chain connectors |
| `scripts/deploy-token-listing-proxy.ts` | Deploy token listings |
| `scripts/deploy-bundle-listing-proxy.ts` | Deploy bundle system |
| `scripts/deploy-multi-token-marketplace.ts` | Deploy marketplace |
| `scripts/deploy-sweep-proxy.ts` | Deploy sweep operations |
| `scripts/deploy-scid-registry.ts` | Deploy SCid registry |

---

## What's Left To Do

### 1. Create Gnosis Safe Wallets (YOU MUST DO THIS)

Create a Gnosis Safe on each chain at [safe.global](https://app.safe.global):

```
# Fill in after creating each Safe

ETHEREUM_SAFE=
POLYGON_SAFE=
ARBITRUM_SAFE=
OPTIMISM_SAFE=
BASE_SAFE=
AVALANCHE_SAFE=
BSC_SAFE=
FANTOM_SAFE=
ZETACHAIN_SAFE=
BLAST_SAFE=
LINEA_SAFE=
SCROLL_SAFE=
ZKSYNC_SAFE=
MANTLE_SAFE=
MANTA_SAFE=
MODE_SAFE=
CELO_SAFE=
GNOSIS_SAFE=
MOONBEAM_SAFE=
AURORA_SAFE=
CRONOS_SAFE=
KAVA_SAFE=
METIS_SAFE=
```

**Setup per Safe:**
- Owners: 2-3 hardware wallet addresses (Ledger/Trezor)
- Threshold: 2 of 3 signatures required
- Name: `SoundChain-[ChainName]`

### 2. Deploy Contracts (Deployment Order)

```bash
# Step 1: Deploy OmnichainRouter on ZetaChain first
export FEE_COLLECTOR=$ZETACHAIN_SAFE
npx hardhat run scripts/deploy-omnichain-router.ts --network zetachain

# Step 2: Save the OmnichainRouter address
export OMNICHAIN_ROUTER=0x... # from step 1

# Step 3: Deploy ChainConnector on each chain
npx hardhat run scripts/deploy-chain-connector.ts --network ethereum
npx hardhat run scripts/deploy-chain-connector.ts --network polygon
npx hardhat run scripts/deploy-chain-connector.ts --network base
# ... repeat for all 23 chains

# Step 4: Deploy marketplace contracts on Polygon
npx hardhat run scripts/deploy-token-listing-proxy.ts --network polygon
npx hardhat run scripts/deploy-bundle-listing-proxy.ts --network polygon
npx hardhat run scripts/deploy-multi-token-marketplace.ts --network polygon
npx hardhat run scripts/deploy-sweep-proxy.ts --network polygon
npx hardhat run scripts/deploy-scid-registry.ts --network polygon
```

### 3. Update Fee Collectors After Deployment

Run this for each deployed contract:
```solidity
// Call these functions to set Gnosis Safe as fee collector
contract.setFeeCollector(GNOSIS_SAFE_ADDRESS)
contract.setGnosisSafe(GNOSIS_SAFE_ADDRESS)
```

### 4. Verify Contracts on Block Explorers

```bash
npx hardhat verify --network polygon $CONTRACT_ADDRESS
npx hardhat verify --network ethereum $CONTRACT_ADDRESS
# ... repeat for each chain
```

---

## Fee Collection Architecture

```
User Transaction on Any Chain
          │
          ▼
    ChainConnector (spoke)
          │
          ▼
    OmnichainRouter (ZetaChain hub)
          │
          ▼
    0.05% Fee Extracted
          │
          ├──▶ Native token stays on chain
          │
          ▼
    Gnosis Safe (per chain)
```

### Revenue Streams (23 chains)

| Chain | Native Fee Token | Gnosis Safe |
|-------|------------------|-------------|
| Ethereum | ETH | TBD |
| Polygon | MATIC | TBD |
| Base | ETH | TBD |
| Arbitrum | ETH | TBD |
| Optimism | ETH | TBD |
| BSC | BNB | TBD |
| Avalanche | AVAX | TBD |
| ZetaChain | ZETA | TBD |
| Blast | ETH | TBD |
| Linea | ETH | TBD |
| Scroll | ETH | TBD |
| zkSync | ETH | TBD |
| Mantle | MNT | TBD |
| Manta | ETH | TBD |
| Mode | ETH | TBD |
| Celo | CELO | TBD |
| Gnosis | xDAI | TBD |
| Moonbeam | GLMR | TBD |
| Aurora | ETH | TBD |
| Cronos | CRO | TBD |
| Kava | KAVA | TBD |
| Metis | METIS | TBD |
| Solana | SOL | TBD |

---

## Token Support

### 24 Supported Tokens

1. ETH, MATIC, SOL, BNB, AVAX, ZETA (native chains)
2. USDC, USDT (stablecoins - most chains)
3. LINK, SHIB, PEPE, DOGE, BONK (meme/DeFi)
4. BTC, LTC, XRP (wrapped versions)
5. XTZ, SUI, HBAR (non-EVM - bridge required)
6. OGUN, YZY, MEATEOR, PENGU, BASE (custom/ecosystem)

### Token Mapping File

See `config/token-chain-mapping.json` for complete addresses.

---

## Non-EVM Chains

### Solana (Ready)
- Programs written in `programs/soundchain-scid/` and `programs/soundchain-marketplace/`
- Deploy with Anchor CLI

### Planned (ZetaChain Bridge)
- Bitcoin, Litecoin, Dogecoin (native)
- All accessible via ZRC-20 tokens on ZetaChain

### Requires Custom Integration
- XRP Ledger, Tezos, Sui, Hedera
- Accept wrapped versions on EVM chains for now

---

## API Integration (Already Done)

### Auto SCid Registration
Location: `api/src/resolvers/TrackResolver.ts`

```typescript
// When NFT is minted, SCid is auto-registered on-chain
if (changes.nftData?.tokenId !== undefined && changes.nftData?.contract) {
  await scidService.registerOnChain(scid, ownerWallet, tokenId, contract, metadataHash, chainId);
}
```

### Required Environment Variables (API)
```bash
SCID_REGISTRY_ADDRESS=0x...
SCID_REGISTRY_PRIVATE_KEY=0x...
POLYGON_RPC_URL=https://polygon-rpc.com
```

---

## Security Checklist

- [ ] All Gnosis Safes use hardware wallets as signers
- [ ] 2-of-3 threshold on all Safes
- [ ] Contracts verified on block explorers
- [ ] Private keys stored in secure vault (not in code)
- [ ] Fee collector addresses double-checked before deployment
- [ ] Test on testnets before mainnet

---

## Testnet Deployment (Recommended First)

```bash
# Polygon Amoy testnet
npx hardhat run scripts/deploy-scid-registry.ts --network amoy

# ZetaChain testnet
npx hardhat run scripts/deploy-omnichain-router.ts --network zetachain_testnet

# Base Sepolia
npx hardhat run scripts/deploy-chain-connector.ts --network base_sepolia
```

---

## Contact & Resources

- **ZetaChain Docs**: https://docs.zetachain.com
- **Gnosis Safe**: https://app.safe.global
- **OpenZeppelin**: https://docs.openzeppelin.com

---

## Git Commits Made

1. `a1dba42b4` - fix: Add ethers dependency for SCidContract (API)
2. `e33b128` - feat: Complete omnichain contract suite with Solana support

---

**Next Step**: Create Gnosis Safe wallets on each chain, then deploy!

---

*This handoff was generated on December 20, 2025. Happy holidays! 🎄*
