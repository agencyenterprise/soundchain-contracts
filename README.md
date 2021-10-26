# Soundchain

This repo contains the smart contracts (ERC1155, Marketplace) for Soundchain.

The ERC1155 is the default implementation with openzeppelin, but we created a extension to have a specific URI to IPFS to each token. Marketplace was originally inspired on the contracts by [Artion](https://github.com/Fantom-foundation/Artion-Contracts).

Deploy is made using AWS KMS, this way, we devs don't have access to the private key that will be used to deploy the contracts and have special powers to set addresses and other information about the contract. Check [aws-kms-provider](https://github.com/odanado/aws-kms-provider)

## Setup

- `yarn`

## Compile

To generate artifacts like ABI and more

- `yarn compile`

## Test

- `yarn test`

## Deploy

To deploy to mainnet

- `yarn deploy:mainnet`

To deploy to testnet

- `yarn deploy:testnet`
