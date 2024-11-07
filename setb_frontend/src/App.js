import React, { useState, useEffect } from 'react';
import Web3 from 'web3';
import customLogo from './customLogo.svg'; 
import './App.css';
import contractABI from './path/to/your/contractABI.json';

const contractABI = [/* ABI of your contract */];
const contractAddress = '0xYourContractAddress'; // Replace with your contract address

function App() {
  const [sourceAsset, setSourceAsset] = useState('sETB');
  const [targetAsset, setTargetAsset] = useState('sETB');
  const [sourceChain, setSourceChain] = useState('Unichain');
  const [targetChain, setTargetChain] = useState('Unichain');
  const [targetAddress, setTargetAddress] = useState('');
  const [useBankRate, setUseBankRate] = useState(false);
  const [marketRate, setMarketRate] = useState(null);
  const [bankRate, setBankRate] = useState(null);
  const [amount, setAmount] = useState('');

  useEffect(() => {
    // Fetch market rate from Uniswap (mocked for this example)
    setMarketRate(100); // Replace with actual API call

    // Fetch bank exchange rate
    fetch('https://api.nbe.gov.et/api/get-selected-exchange-rates')
      .then(response => response.json())
      .then(data => {
        const rate = data.find(rate => rate.currency === 'USD');
        setBankRate(rate ? rate.rate : null);
      });
  }, []);

  const handleSwap = async () => {
    if (window.ethereum) {
      const web3 = new Web3(window.ethereum);
      await window.ethereum.enable();
      const contract = new web3.eth.Contract(contractABI, contractAddress);
      const accounts = await web3.eth.getAccounts();
      const chainIdMap = {
        'Unichain': 1,
        'Scroll': 2,
        'Ethereum': 3
      };
      const destChainId = chainIdMap[targetChain];
      const desiredOutputToken = targetAsset === 'sETB' ? '0xAddressOfsETB' : targetAsset === 'ETH' ? '0xAddressOfETH' : '0xAddressOfUSDC';

      contract.methods.bridge(destChainId, targetAddress, web3.utils.toWei(amount, 'ether'), desiredOutputToken, useBankRate)
        .send({ from: accounts[0] })
        .on('receipt', function(receipt){
          console.log('Transaction receipt: ', receipt);
        });
    } else {
      console.log('MetaMask is not installed');
    }
  };

  return (
    <div className="App">
      <header className="App-header">
        <img src={customLogo} className="App-logo" alt="logo" />
        <h1>LayerSwap</h1>
        <form>
          <div>
            <label>Source Asset:</label>
            <select value={sourceAsset} onChange={e => setSourceAsset(e.target.value)}>
              <option value="sETB">sETB</option>
              <option value="ETH">Ether</option>
              <option value="USDC">USDC</option>
            </select>
          </div>
          <div>
            <label>Target Asset:</label>
            <select value={targetAsset} onChange={e => setTargetAsset(e.target.value)}>
              <option value="sETB">sETB</option>
              <option value="ETH">Ether</option>
              <option value="USDC">USDC</option>
            </select>
          </div>
          <div>
            <label>Source Chain:</label>
            <select value={sourceChain} onChange={e => setSourceChain(e.target.value)}>
              <option value="Unichain">Unichain</option>
              <option value="Scroll">Scroll</option>
              <option value="Ethereum">Ethereum (Sepolia)</option>
            </select>
          </div>
          <div>
            <label>Target Chain:</label>
            <select value={targetChain} onChange={e => setTargetChain(e.target.value)}>
              <option value="Unichain">Unichain</option>
              <option value="Scroll">Scroll</option>
              <option value="Ethereum">Ethereum (Sepolia)</option>
            </select>
          </div>
          <div>
            <label>Target Address:</label>
            <input type="text" value={targetAddress} onChange={e => setTargetAddress(e.target.value)} />
          </div>
          <div>
            <label>Amount:</label>
            <input type="text" value={amount} onChange={e => setAmount(e.target.value)} />
          </div>
          <div>
            <label>Use Bank exchange rate for USD?</label>
            <input type="checkbox" checked={useBankRate} onChange={e => setUseBankRate(e.target.checked)} />
          </div>
          <button type="button" onClick={handleSwap}>Swap</button>
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