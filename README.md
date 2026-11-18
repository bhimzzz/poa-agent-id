# POA — Proof of Agent

An Agent-ID-native launch system on **BNB Smart Chain**. Access to the product is
gated on-chain by **Binance Agent ID**: the mint contracts check the caller's wallet
against the SPACE ID Agent ID registry before any mint is allowed. Only Agent ID
holders can participate — across the token, the NFT collection, and the marketplace.

- Website: https://poagi.top
- X: https://x.com/poagirh
- Submitted to the Binance Wallet × BNB Chain **Agent ID Hackathon** (Nov–Dec 2026)

## How Agent ID is used

The mint contracts query the Agent ID registry
(`0x60b9262456de011f7d15a54cdd8c48baaa8b022f`, ERC-721) and require
`balanceOf(caller) > 0` before a mint executes. This makes Agent ID the identity
and access layer of the whole product:

- **Token mint** — Agent ID holders mint the POA token (fixed supply 1,000,000,000,
  distributed through 100,000 mint calls).
- **NFT mint** — a 2,500-piece collection; the first 1,000 were free and reserved
  exclusively for Agent ID holders (free phase completed: 1,000 minted), followed by
  a paid phase at 0.0015 BNB.
- **Marketplace** — holders trade the NFTs peer-to-peer (4% market fee).

## Contracts (BNB Smart Chain, source-verified — Sourcify exact match)

| Contract | Address | BscScan |
|---|---|---|
| Token (POA) | `0xf4dc5fbe3c9af9ef8da7fb746f9a2ebfe34eef47` | https://bscscan.com/address/0xf4dc5fbe3c9af9ef8da7fb746f9a2ebfe34eef47 |
| Mint | `0x67b1bd2dccb76691b938e9f0c861210ec0ce3324` | https://bscscan.com/address/0x67b1bd2dccb76691b938e9f0c861210ec0ce3324 |
| NFT | `0x4d0923060d6f657df4c2567b629e1c3ab8dbc5f5` | https://bscscan.com/address/0x4d0923060d6f657df4c2567b629e1c3ab8dbc5f5 |
| Market | `0x4cb4083746193226bc489d52fae8f0bef10f9eec` | https://bscscan.com/address/0x4cb4083746193226bc489d52fae8f0bef10f9eec |

The `.sol` sources in this repository are the exact verified sources of the
deployed contracts, as published on Sourcify.

## Owner permissions (disclosed)

- Token tax is fixed at deployment (6% buy / 6% sell) and **cannot be changed**.
- Configuration is locked after setup (`setupLocked`); supply caps are hard-coded.
- The owner retains one pending one-time action: `openTrading`, which enables
  token transfers after the owner seeds the liquidity pool.
- No function allows the owner to mint beyond the caps, change the tax, pause
  trading, freeze wallets, or withdraw user assets.

## Risk notice

POA is a crypto asset; prices are volatile and the token/NFTs can lose value.
Nothing in this project promises returns.

## License

MIT
