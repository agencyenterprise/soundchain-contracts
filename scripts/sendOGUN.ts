import { KmsProvider } from "aws-kms-provider";
import dotenv from "dotenv";
import { ethers, run } from "hardhat";
import Web3 from "web3";
import { AbiItem } from 'web3-utils';
import SoundchainOGUN20 from '../artifacts/contracts/SoundchainOGUN20.sol/SoundchainOGUN20.json';

dotenv.config();

const region = "us-east-1";

const { AWS_KMS_KEY_ID, POLYGON_ALCHEMY_URL, TO, AMOUNT } = process.env;

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

  console.log(`$$ Sending ${AMOUNT} OGUN to ${TO}...`);

  const adminWallet = await getAdminWallet();

  const ogunContract = new web3.eth.Contract(
    SoundchainOGUN20.abi as AbiItem[],
    process.env.OGUN_TOKEN_ADDRESS,
  );

  const tokenAmount = await ogunContract.methods.balanceOf(adminWallet).call();
  console.log('current balance: ', tokenAmount, 'OGUN')

  const amountWei = web3.utils.toWei(AMOUNT)
  const txObj = await ogunContract.methods.transfer(TO, amountWei);
  const SoundchainOGUN20Receipt = await txObj.send({ from: adminWallet, TO, value: "0x00" })

  console.log('tx hash: ', SoundchainOGUN20Receipt?.transactionHash)
  console.log('return values: ', SoundchainOGUN20Receipt?.events?.Transfer.returnValues)
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
