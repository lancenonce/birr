import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: any) {
	const { deployer } = await hre.getNamedAccounts();
	const { deploy } = hre.deployments;

	await deploy("ETB", {
		from: deployer,
		args: [],
		log: true,
	});

	return hre.network.live;
};

export default func;
func.id = "deploy_hello_etb";
func.tags = ["ETB"];
func.dependencies = [];
