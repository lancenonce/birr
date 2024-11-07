import fs from 'fs';
import { task } from "hardhat/config";
import { getChainConfig } from "@vialabs-io/npm-registry";
import networks from "../networks";

task("configure", "")
	.addOptionalParam("signer", "Custom signer (private key)")
	.addOptionalParam("provider", "Custom provider RPC url")
	.setAction(async (args, hre:any) => {
		const ethers = hre.ethers;
		const [deployer] = await ethers.getSigners();

		let signer = deployer;
		if (args.signer) signer = new ethers.Wallet(args.signer, new ethers.providers.JsonRpcProvider(args.provider));
		
		let addresses = [];
		let chainids = [];
		let confirmations=[];
		for(let x=0; x < networks.length; x++) {
			const etb = require(process.cwd()+"/deployments/"+networks[x]+"/ETB.json");
			const chainId = fs.readFileSync(process.cwd()+"/deployments/"+networks[x]+"/.chainId").toString();
			addresses.push(etb.address);
			chainids.push(chainId);
			confirmations.push(1);
		}
	
		const chainConfig = getChainConfig(hre.network.config.chainId);
		if (!chainConfig) {
			throw new Error(`Chain configuration not found for chainId: ${hre.network.config.chainId}`);
		}

		console.log('setting remote contract addresses .. VIA message gateway address:', chainConfig.message);
		const etb = await ethers.getContract("ETB");
		await (await etb.configureClient(chainConfig.message, chainids, addresses, confirmations)).wait();
	});
