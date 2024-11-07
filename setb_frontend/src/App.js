import React, { useState, useEffect } from "react";
import Web3 from "web3";
import customLogo from "./customLogo.svg";
import "./App.css";
import contractABIJSON from "./abi/ETB.json";

const contractAddress = "0x7b230BE939C5A7795938916e4F7409B5e0880F4C";
const contractABI = contractABIJSON.abi;
const sepoliaChainId = 11155111;

function App() {
  const [sourceAsset, setSourceAsset] = useState("sETB");
  const [targetAsset, setTargetAsset] = useState("sETB");
  const [sourceChain, setSourceChain] = useState("Ethereum");
  const [targetChain, setTargetChain] = useState("Ethereum");
  const [targetAddress, setTargetAddress] = useState("");
  const [useBankRate, setUseBankRate] = useState(false);
  const [marketRate, setMarketRate] = useState(null);
  const [bankRate, setBankRate] = useState(null);
  const [amount, setAmount] = useState("");

  useEffect(() => {
    // Fetch market rate from Uniswap (mocked for this example)
    setMarketRate(121.47); // Replace with actual API call

    // Fetch bank exchange rate
    fetch("https://api.nbe.gov.et/api/get-selected-exchange-rates")
      .then((response) => response.json())
      .then((data) => {
        console.log("API response:", data);

        if (data && data.data && Array.isArray(data.data)) {
          // Find the rate for USD
          const usdRate = data.data.find(
            (rate) => rate.currency.code === "USD"
          );

          // Set bank rate to the "buying" value for USD if found
          if (usdRate) {
            setBankRate(usdRate.buying);
            console.log("USD Buying Rate:", usdRate.buying);
          } else {
            console.error("USD rate not found in API response.");
          }
        } else {
          console.error("Unexpected API response format:", data);
        }
      })
      .catch((error) => {
        console.error("Error fetching bank exchange rate:", error);
      });
  }, []);

  const getDesiredOutputToken = (targetChain, targetAsset) => {
    if (targetChain === "Unichain" && targetAsset === "sETB") {
      return "0xdD3324AB2e26268E15c792Cb8c1f0eD8bA9A4C76";
    } else if (targetChain === "Ethereum" && targetAsset === "sETB") {
      return "0x7b230BE939C5A7795938916e4F7409B5e0880F4C";
    } else if (targetChain === "Ethereum" && targetAsset === "USDC") {
      return "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238";
    } else if (targetChain === "Unichain" && targetAsset === "USDC") {
      throw new Error("USDC is unsupported on Unichain");
    } else {
      throw new Error("Unsupported target chain or asset");
    }
  };

  const handleSwap = async () => {
    try {
      const desiredOutputToken = "0x7b230BE939C5A7795938916e4F7409B5e0880F4C";
  
      if (window.ethereum) {
        const web3 = new Web3(window.ethereum);
        await window.ethereum.enable();
        const currentChainId = await web3.eth.getChainId();
  
        // Check if the current network is Sepolia (chain ID 11155111)
        if (currentChainId !== 11155111) {
          try {
            await window.ethereum.request({
              method: 'wallet_switchEthereumChain',
              params: [{ chainId: Web3.utils.toHex(11155111) }],
            });
          } catch (switchError) {
            if (switchError.code === 4902) {
              console.error("Sepolia Ethereum network is not added to MetaMask");
            } else {
              console.error("Failed to switch network:", switchError);
            }
            return; 
          }
        }
  
        const contract = new web3.eth.Contract(contractABI, contractAddress);
        const accounts = await web3.eth.getAccounts();
        const chainIdMap = {
          Unichain: 1301,
          Ethereum: 11155111,
        };
        const destChainId = chainIdMap[targetChain];
  
        contract.methods
          .bridge(
            destChainId,
            targetAddress,
            web3.utils.toWei(amount, "ether"),
            desiredOutputToken,
            useBankRate
          )
          .send({ from: accounts[0] })
          .on("receipt", function (receipt) {
            console.log("Transaction receipt: ", receipt);
          });
      } else {
        console.log("MetaMask is not installed");
      }
    } catch (error) {
      console.error(error.message);
    }
  };

  return (
    <div className="App">
      <header className="App-header">
        <img src={customLogo} className="App-logo" alt="logo" />
        <h1>good rates</h1>
        <form>
          <div>
            <label>Source Asset:</label>
            <select
              value={sourceAsset}
              onChange={(e) => setSourceAsset(e.target.value)}
            >
              <option value="sETB">sETB</option>
              <option value="USDC">USDC</option>
            </select>
          </div>
          <div>
            <label>Target Asset:</label>
            <select
              value={targetAsset}
              onChange={(e) => setTargetAsset(e.target.value)}
            >
              <option value="sETB">sETB</option>
              <option value="USDC">USDC</option>
            </select>
          </div>
          <div>
            <label>Source Chain:</label>
            <select
              value={sourceChain}
              onChange={(e) => setSourceChain(e.target.value)}
            >
              <option value="Unichain">Unichain</option>
              <option value="Ethereum">Ethereum (Sepolia)</option>
            </select>
          </div>
          <div>
            <label>Target Chain:</label>
            <select
              value={targetChain}
              onChange={(e) => setTargetChain(e.target.value)}
            >
              <option value="Unichain">Unichain</option>
              <option value="Ethereum">Ethereum (Sepolia)</option>
            </select>
          </div>
          <div>
            <label>Target Address:</label>
            <input
              type="text"
              value={targetAddress}
              onChange={(e) => setTargetAddress(e.target.value)}
            />
          </div>
          <div>
            <label>Amount:</label>
            <input
              type="text"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          </div>
          <div>
            <label>Use Bank exchange rate for USD?</label>
            <input
              type="checkbox"
              checked={useBankRate}
              onChange={(e) => setUseBankRate(e.target.checked)}
            />
          </div>
          <button type="button" onClick={handleSwap}>
            Swap
          </button>
        </form>
        <div className="price-feed">
          <h2>Price Feed</h2>
          <p>Market Rate (Uniswap): {marketRate}</p>
          <p>Official Bank Exchange Rate: {bankRate}</p>
        </div>
      </header>
    </div>
  );
}

export default App;
