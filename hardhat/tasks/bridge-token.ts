import { task } from "hardhat/config";

task("bridge-token", "")
	.addParam("dest", "Destination chain id")
	.addParam("amount", "Amount of tokens in ETH")
	.addOptionalParam("wallet", "Custom wallet")
	.addOptionalParam("signer", "Custom signer (private key)")
	.addOptionalParam("provider", "Custom provider RPC url")
	.setAction(async (args, hre: any) => {
		const ethers = hre.ethers;
		const network = hre.network.name;
		const [deployer] = await ethers.getSigners();

		let signer = deployer;
		let wallet = deployer.address;
		if (args.signer) signer = new ethers.Wallet(args.signer, new ethers.providers.JsonRpcProvider(args.provider));
		if (args.wallet) wallet = args.wallet;

		const etb = await ethers.getContract("ETB");

		await (await etb.connect(signer).approve(signer.address, ethers.parseEther(args.amount))).wait();

		await etb.connect(signer).bridge.estimateGas(args.dest, wallet, ethers.parseEther(args.amount));
		await (await etb.connect(signer).bridge(args.dest, wallet, ethers.parseEther(args.amount))).wait();

		console.log("sent", args.amount, " of tokens to", wallet, "on chain id", args.dest);
	});
