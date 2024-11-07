import { task } from "hardhat/config";

task("get-token-balance", "")
	.addOptionalParam("wallet", "Custom wallet")
	.addOptionalParam("signer", "Custom signer (private key)")
	.addOptionalParam("provider", "Custom provider RPC url")
	.setAction(async (args, hre:any) => {
		const ethers = hre.ethers;
		const network = hre.network.name;
		const [deployer] = await ethers.getSigners();
        
		let signer = deployer;
		let wallet = deployer.address;
		if (args.signer) signer = new ethers.Wallet(args.signer, new ethers.providers.JsonRpcProvider(args.provider));
		if (args.wallet) wallet = args.wallet; 

		const etb = await ethers.getContract("ETB");
		const balance = await etb.connect(signer).balanceOf(wallet);
		console.log(wallet, 'has a balance of', ethers.formatEther(balance));
	});
