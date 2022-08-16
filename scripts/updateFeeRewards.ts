/*
 * ###################### DISCLAIMER PLEASE READ BEFORE EXECUTING ######################
 * This script allows you to update the reward fee of the marketplace contract
 * be sure to update it accordingly and in balance with the platform fee to prevent
 * white washing, meaning, the rewards can't be higher than the platform fee otherwise
 * users will be able to earn infinite money from trading with themselves.
 * #####################################################################################
 */
import { KmsProvider } from "aws-kms-provider";
import dotenv from "dotenv";
import Web3 from "web3";
import { AbiItem } from "web3-utils";
import MarketplaceABI from "../abi/contracts/MarketplaceEditions.sol/SoundchainMarketplaceEditions.json";

dotenv.config();

const region = "us-east-1";

const {
  AWS_KMS_KEY_ID,
  MAINNET_URL,
  MARKETPLACE_EDITIONS_CONTRACT_ADDRESS,
  REWARDS_RATE,
} = process.env;

const provider = new KmsProvider(MAINNET_URL, {
  region,
  keyIds: [AWS_KMS_KEY_ID],
});

const web3 = new Web3(provider);

const getAdminWallet = async () => {
  const accounts = await web3.eth.getAccounts();
  return accounts[0];
};

const getSignedTransaction = async (data, to) => {
  const from = await getAdminWallet();
  const nonce = await web3.eth.getTransactionCount(from);
  const transaction = {
    from,
    data,
    nonce,
    to,
  };
  return await web3.eth.signTransaction(transaction, from);
};

const sendSignedTransaction = async (signedTransaction) => {
  return await web3.eth.sendSignedTransaction(signedTransaction);
};

const main = async () => {
  const marketplaceContract = new web3.eth.Contract(
    MarketplaceABI as AbiItem[],
    MARKETPLACE_EDITIONS_CONTRACT_ADDRESS
  );
  // This is where we are defining the amount of the reward fee
  const encodedData = await marketplaceContract.methods
    .setRewardsRate(REWARDS_RATE)
    .encodeABI();
  const signedTransaction = await getSignedTransaction(
    encodedData,
    MARKETPLACE_EDITIONS_CONTRACT_ADDRESS
  );
  await sendSignedTransaction(signedTransaction.raw);
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
