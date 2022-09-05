import { KmsProvider } from "aws-kms-provider";
import dotenv from "dotenv";
import readline from 'readline';
import { ethers, run } from "hardhat";
import Web3 from "web3";
import { AbiItem } from 'web3-utils';
import MerkleClaimERC20 from '../artifacts/contracts/MerkleClaimERC20.sol/MerkleClaimERC20.json';
import LiquidityPoolRewards from '../artifacts/contracts/LiquidityPoolRewards.sol/LiquidityPoolRewards.json';
import StakingRewards from '../artifacts/contracts/StakingRewards.sol/StakingRewards.json';
import SoundchainMarketplaceEditions from '../artifacts/contracts/MarketplaceEditions.sol/SoundchainMarketplaceEditions.json';

dotenv.config();

const contracts = {
  MerkleClaimERC20,
  LiquidityPoolRewards,
  StakingRewards,
  SoundchainMarketplaceEditions,
}

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});

const prompt = (msg) => {
  return (new Promise((resolve, reject) => {
    rl.question(msg, (reply) => resolve(reply));
  }));
}

const region = "us-east-1";

const { AWS_KMS_KEY_ID, POLYGON_ALCHEMY_URL, TO } = process.env;

const provider = new KmsProvider(POLYGON_ALCHEMY_URL, {
  region,
  keyIds: [AWS_KMS_KEY_ID],
});

const web3 = new Web3(provider);

const getAdminWallet = async () => {
  const accounts = await web3.eth.getAccounts();
  return accounts[0];
};

const main = async () => {
  const contractName: string = await prompt('Please specify the contract name [MerkleClaimERC20, LiquidityPoolRewards, StakingRewards, SoundchainMarketplaceEditions]:\n') as string;

  if (!contracts[contractName]) throw new Error(`${contractName} does not appear to exist or is not imported.`);

  const contractAddress: string = await prompt('Please specify the contract address:\n') as string;
  const transferTo = await prompt('Please specify the address of the wallet to transfer ownership to:\n');


  console.log(`$$ Reclaiming all OGUN from the ${contractName} contract and sending it to ${TO}...`);

  const adminWallet = await getAdminWallet();

  const specificContract = new web3.eth.Contract(
    contracts[contractName].abi as AbiItem[],
    contractAddress,
  );

  const method = specificContract.methods.reclaimOgun || specificContract.methods.withdraw;

  const txObj = await method(transferTo);
  const receipt = await txObj.send({ from: adminWallet, transferTo, value: "0x00" })

  console.log('tx hash: ', receipt?.transactionHash)
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
